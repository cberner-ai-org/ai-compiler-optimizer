#!/usr/bin/env bash
set -euo pipefail

proof_dir="${1:?usage: verify-alive2-proofs PROOF_DIRECTORY}"
alive2_bin="${ALIVE2_BIN:-/usr/local/bin/alive}"
alive2_tv_bin="${ALIVE2_TV_BIN:-/usr/local/bin/alive-tv}"
smt_timeout_ms="${ALIVE2_SMT_TIMEOUT_MS:-60000}"
process_timeout_seconds="${ALIVE2_PROCESS_TIMEOUT_SECONDS:-90}"
memory_limit_mb="${ALIVE2_MEMORY_LIMIT_MB:-1024}"

fail() {
    echo "Alive2 proof rejected: $*" >&2
    exit 1
}

[[ -x "${alive2_bin}" ]] || fail "verifier is not executable: ${alive2_bin}"
[[ -x "${alive2_tv_bin}" ]] \
    || fail "translation validator is not executable: ${alive2_tv_bin}"
[[ -d "${proof_dir}" ]] || fail "proof directory does not exist: ${proof_dir}"
[[ "${smt_timeout_ms}" =~ ^[1-9][0-9]*$ ]] || fail "SMT timeout must be positive"
[[ "${process_timeout_seconds}" =~ ^[1-9][0-9]*$ ]] \
    || fail "process timeout must be positive"
[[ "${memory_limit_mb}" =~ ^[1-9][0-9]*$ ]] || fail "memory limit must be positive"

shopt -s nullglob
proofs=("${proof_dir}"/*.opt)
llvm_proofs=("${proof_dir}"/*.srctgt.ll)
proofs+=("${llvm_proofs[@]}")
(( ${#proofs[@]} > 0 )) \
    || fail "no .opt or .srctgt.ll proof obligations found in ${proof_dir}"

log_dir="$(mktemp -d)"
trap 'rm -rf -- "${log_dir}"' EXIT

for proof in "${proofs[@]}"; do
    proof_name="$(basename -- "${proof}")"
    stdout_path="${log_dir}/${proof_name}.stdout"
    stderr_path="${log_dir}/${proof_name}.stderr"

    verifier=(
        "${alive2_bin}"
        -root-only
        "-smt-to:${smt_timeout_ms}"
        "-max-mem:${memory_limit_mb}"
    )
    expected_success='Transformation seems to be correct!'
    if [[ "${proof}" == *.srctgt.ll ]]; then
        verifier=(
            "${alive2_tv_bin}"
            "-smt-to=${smt_timeout_ms}"
            "-smt-max-mem=${memory_limit_mb}"
            -fail-src-ub
            -exit-on-error
        )
        expected_success='Transformation seems to be correct!'
    fi

    if timeout --signal=KILL "${process_timeout_seconds}" \
        "${verifier[@]}" "${proof}" \
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

    # A proof result is a protocol, not a substring search. Both frontends emit
    # an informational transformation transcript, and alive-tv can put semantic
    # warnings (including an always-UB source warning) in that same stream.
    # Require one unqualified success and reject Alive2's diagnostic records on
    # either stream. -fail-src-ub additionally makes that unsafe proof shape a
    # verifier error instead of relying only on output parsing.
    success_count="$(grep --fixed-strings --line-regexp --count \
        "${expected_success}" "${stdout_path}" || true)"
    if [[ "${success_count}" != 1 ]] \
        || grep --quiet --extended-regexp \
            '(WARNING|ERROR|NOTE):|Transformation doesn.t verify!|Unsupported' \
            "${stdout_path}"; then
        sed -n '1,160p' "${stdout_path}" >&2
        fail "${proof_name} did not produce one unqualified success result"
    fi

    printf 'Alive2 proved %s\n' "${proof_name}"
done
