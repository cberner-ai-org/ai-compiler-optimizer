#!/usr/bin/env bash
set -euo pipefail

proof_dir="${1:?usage: verify-alive2-negative-proofs PROOF_DIRECTORY}"
alive2_bin="${ALIVE2_BIN:-/usr/local/bin/alive}"
smt_timeout_ms="${ALIVE2_SMT_TIMEOUT_MS:-10000}"
process_timeout_seconds="${ALIVE2_PROCESS_TIMEOUT_SECONDS:-30}"
memory_limit_mb="${ALIVE2_MEMORY_LIMIT_MB:-1024}"

fail() {
    echo "Alive2 negative proof rejected: $*" >&2
    exit 1
}

[[ -x "${alive2_bin}" ]] || fail "verifier is not executable: ${alive2_bin}"
[[ -d "${proof_dir}" ]] || fail "proof directory does not exist: ${proof_dir}"
[[ "${smt_timeout_ms}" =~ ^[1-9][0-9]*$ ]] || fail "SMT timeout must be positive"
[[ "${process_timeout_seconds}" =~ ^[1-9][0-9]*$ ]] \
    || fail "process timeout must be positive"
[[ "${memory_limit_mb}" =~ ^[1-9][0-9]*$ ]] || fail "memory limit must be positive"

shopt -s nullglob
proofs=("${proof_dir}"/*.opt)
(( ${#proofs[@]} > 0 )) || fail "no .opt negative obligations found in ${proof_dir}"

fixture_root="$(mktemp -d)"
trap 'rm -rf -- "${fixture_root}"' EXIT

for proof in "${proofs[@]}"; do
    proof_name="$(basename -- "${proof}")"
    stdout_path="${fixture_root}/${proof_name}.stdout"
    stderr_path="${fixture_root}/${proof_name}.stderr"

    if timeout --signal=KILL "${process_timeout_seconds}" \
        "${alive2_bin}" \
        "-smt-to:${smt_timeout_ms}" \
        "-max-mem:${memory_limit_mb}" \
        "${proof}" \
        >"${stdout_path}" \
        2>"${stderr_path}"; then
        :
    else
        status="$?"
        sed -n '1,160p' "${stdout_path}" >&2
        sed -n '1,160p' "${stderr_path}" >&2
        fail "${proof_name} exited with status ${status}"
    fi

    if ! awk -v expected_processing="Processing ${proof}.." '
        $0 == expected_processing { processing_count++; next }
        $0 == "----------------------------------------" { separator_count++; next }
        /^Name: / { name_count++; next }
        $0 == "=>" { arrow_count++; next }
        $0 == "Transformation seems to be correct!" { success_count++; next }
        /^[[:space:]]/ { next }
        /^$/ { next }
        { unexpected_count++ }
        END {
            exit !(processing_count == 1 && separator_count == 1 &&
                name_count == 1 && arrow_count == 1 && success_count == 0 &&
                unexpected_count == 0)
        }
    ' "${stdout_path}"; then
        sed -n '1,160p' "${stdout_path}" >&2
        sed -n '1,160p' "${stderr_path}" >&2
        fail "${proof_name} did not report exactly one failed transformation"
    fi

    # Alive2 returns zero for a disproved transformation. Accept only its exact
    # scalar counterexample structure; any extra diagnostic is an unknown
    # verifier outcome rather than evidence that this negative control worked.
    first_error="$(sed -n '1p' "${stderr_path}")"
    case "${first_error}" in
        "ERROR: Value mismatch for "?* | \
            "ERROR: Target's return value is more undefined for "?*)
            ;;
        *)
            sed -n '1,160p' "${stdout_path}" >&2
            sed -n '1,160p' "${stderr_path}" >&2
            fail "${proof_name} reported an unrecognized Alive2 error"
            ;;
    esac

    if ! awk '
        NR == 1 {
            if ($0 !~ /^ERROR: /)
                invalid = 1
            error_count++
            phase = 1
            next
        }
        /^$/ { next }
        $0 == "NOTE: The counterexample is unique." {
            if (phase != 1 || note_count++ != 0)
                invalid = 1
            next
        }
        $0 == "Example:" {
            if (phase != 1 || example_count++ != 0)
                invalid = 1
            phase = 2
            next
        }
        /^i[0-9]+ %[A-Za-z0-9._-]+ = .+$/ {
            if (phase != 2)
                invalid = 1
            model_count++
            next
        }
        /^Source value: .+$/ {
            if (phase != 2 || source_count++ != 0)
                invalid = 1
            phase = 3
            next
        }
        /^Target value: .+$/ {
            if (phase != 3 || target_count++ != 0)
                invalid = 1
            phase = 4
            next
        }
        { invalid = 1 }
        END {
            exit !(invalid == 0 && error_count == 1 && example_count == 1 &&
                model_count > 0 && source_count == 1 && target_count == 1 &&
                phase == 4)
        }
    ' "${stderr_path}"; then
        sed -n '1,160p' "${stdout_path}" >&2
        sed -n '1,160p' "${stderr_path}" >&2
        fail "${proof_name} did not produce one clean Alive2 semantic mismatch"
    fi
    printf 'Alive2 rejected %s with a semantic mismatch\n' "${proof_name}"
done
