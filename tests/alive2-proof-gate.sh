#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
verifier="${repo_root}/scripts/verify-alive2-proofs.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf -- "${fixture_root}"' EXIT

mkdir -p "${fixture_root}/proofs"
printf 'fixture\n' > "${fixture_root}/proofs/candidate.opt"

fake_alive="${fixture_root}/alive"
cat > "${fake_alive}" <<'FAKE_ALIVE'
#!/usr/bin/env bash
set -euo pipefail

case "${FAKE_ALIVE_RESULT:?}" in
    correct)
        echo 'Transformation seems to be correct!'
        ;;
    counterexample)
        echo 'ERROR: Value mismatch' >&2
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

echo "Alive2 proof gate regression passed"
