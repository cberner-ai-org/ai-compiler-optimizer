#!/usr/bin/env bash
set -euo pipefail

proof_dir="${1:?usage: verify-alive2-proofs PROOF_DIRECTORY}"
alive2_bin="${ALIVE2_BIN:-/usr/local/bin/alive}"
smt_timeout_ms="${ALIVE2_SMT_TIMEOUT_MS:-10000}"
process_timeout_seconds="${ALIVE2_PROCESS_TIMEOUT_SECONDS:-30}"
memory_limit_mb="${ALIVE2_MEMORY_LIMIT_MB:-1024}"

fail() {
    echo "Alive2 proof rejected: $*" >&2
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
(( ${#proofs[@]} > 0 )) || fail "no .opt proof obligations found in ${proof_dir}"

log_dir="$(mktemp -d)"
trap 'rm -rf -- "${log_dir}"' EXIT

for proof in "${proofs[@]}"; do
    proof_name="$(basename -- "${proof}")"
    stdout_path="${log_dir}/${proof_name}.stdout"
    stderr_path="${log_dir}/${proof_name}.stderr"

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

    if [[ -s "${stderr_path}" ]]; then
        sed -n '1,160p' "${stderr_path}" >&2
        fail "${proof_name} produced diagnostics"
    fi

    success_count="$(grep --fixed-strings --line-regexp --count \
        'Transformation seems to be correct!' \
        "${stdout_path}" || true)"
    if [[ "${success_count}" != 1 ]]; then
        sed -n '1,160p' "${stdout_path}" >&2
        fail "${proof_name} reported ${success_count} successful transformations; expected exactly one"
    fi

    printf 'Alive2 proved %s\n' "${proof_name}"
done
