#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
verifier="${repo_root}/scripts/verify-alive2-proofs.sh"
negative_verifier="${repo_root}/scripts/verify-alive2-negative-proofs.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf -- "${fixture_root}"' EXIT

mkdir -p "${fixture_root}/proofs"
printf 'fixture\n' > "${fixture_root}/proofs/candidate.opt"
printf 'second fixture\n' > "${fixture_root}/proofs/second-candidate.opt"

fake_alive="${fixture_root}/alive"
cat > "${fake_alive}" <<'FAKE_ALIVE'
#!/usr/bin/env bash
set -euo pipefail

root_only=false
for argument in "$@"; do
    if [[ "${argument}" == -root-only ]]; then
        root_only=true
    fi
done
if [[ "${root_only}" != true ]]; then
    echo 'fake Alive2 requires -root-only' >&2
    exit 2
fi

emit_counterexample() {
    proof="${*: -1}"
    printf 'Processing %s..\n\n' "${proof}"
    echo '----------------------------------------'
    echo 'Name: fake inequivalent regression'
    echo '  %result = add i8 %value, 1'
    echo '=>'
    echo '  %result = add i8 %value, 2'
    echo
    echo 'ERROR: Value mismatch' >&2
    echo >&2
    echo 'NOTE: The counterexample is unique.' >&2
    echo >&2
    echo 'Example:' >&2
    if [[ "${FAKE_ALIVE_RESULT}" != counterexample-model-less ]]; then
        echo 'i8 %value = #x03 (3)' >&2
    fi
    echo >&2
    echo 'Source:' >&2
    echo 'i8 %result = #x04 (4)' >&2
    echo >&2
    echo 'Target:' >&2
    echo 'i8 %result = #x05 (5)' >&2
    echo 'Source value: #x04 (4)' >&2
    echo 'Target value: #x05 (5)' >&2
}

case "${FAKE_ALIVE_RESULT:?}" in
    correct)
        echo 'Transformation seems to be correct!'
        ;;
    counterexample|counterexample-model-less)
        emit_counterexample "$@"
        ;;
    counterexample-warning)
        emit_counterexample "$@"
        echo 'WARNING: unsupported feature approximated' >&2
        ;;
    counterexample-timeout)
        emit_counterexample "$@"
        exit 124
        ;;
    counterexample-crash)
        emit_counterexample "$@"
        exit 139
        ;;
    ambiguous)
        echo 'Transformation seems to be correct!'
        echo 'Transformation seems to be correct!'
        ;;
    warning)
        echo 'Transformation seems to be correct!'
        echo 'WARNING: unsupported feature approximated' >&2
        ;;
    timeout)
        exit 124
        ;;
    *)
        exit 2
        ;;
esac
if [[ -n "${FAKE_ALIVE_INVOCATIONS:-}" ]]; then
    printf '%s\n' "${*: -1}" >> "${FAKE_ALIVE_INVOCATIONS}"
fi
FAKE_ALIVE
chmod 0755 "${fake_alive}"

run_gate() {
    FAKE_ALIVE_RESULT="$1" \
        ALIVE2_BIN="${fake_alive}" \
        "${verifier}" "${fixture_root}/proofs" \
        >"${fixture_root}/$1.log" \
        2>&1
}

run_gate correct

for rejected in counterexample ambiguous warning timeout; do
    if run_gate "${rejected}"; then
        echo "Alive2 proof gate accepted ${rejected} output" >&2
        exit 1
    fi
done

invocations="${fixture_root}/negative-invocations.log"
FAKE_ALIVE_RESULT=counterexample \
FAKE_ALIVE_INVOCATIONS="${invocations}" \
ALIVE2_BIN="${fake_alive}" \
    "${negative_verifier}" "${fixture_root}/proofs" \
    >"${fixture_root}/negative.log" \
    2>&1
[[ "$(wc -l < "${invocations}")" == 2 ]]

FAKE_ALIVE_RESULT=counterexample-model-less \
ALIVE2_BIN="${fake_alive}" \
    "${negative_verifier}" "${fixture_root}/proofs" \
    >"${fixture_root}/negative-model-less.log" \
    2>&1

for rejected in correct counterexample-warning counterexample-timeout counterexample-crash; do
    if FAKE_ALIVE_RESULT="${rejected}" \
        ALIVE2_BIN="${fake_alive}" \
            "${negative_verifier}" "${fixture_root}/proofs" \
            >"${fixture_root}/negative-${rejected}.log" \
            2>&1; then
        echo "Alive2 negative gate accepted ${rejected} output" >&2
        exit 1
    fi
done

echo "Alive2 proof gate regression passed"
