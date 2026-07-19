#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
finder="${repo_root}/scripts/find-widened-midpoints.sh"
fixture="${repo_root}/tests/fixtures/widened-midpoints.ll"
output="$(mktemp)"
expected="$(mktemp)"

cleanup() {
    rm -f -- "${output}" "${expected}"
}
trap cleanup EXIT

"${finder}" "${fixture}" > "${output}"

printf '%s\n' \
    $'pattern\tfunction\tline\tleft\tright' \
    $'widened-unsigned-midpoint\tmatch_with_flags\t6\t%left\t%right' \
    $'widened-unsigned-midpoint\tmatch_without_flags\t24\t%b\t%a' \
    > "${expected}"

diff --unified "${expected}" "${output}"

if "${finder}" "${fixture}.missing" > /dev/null 2>&1; then
    echo "IR candidate finder accepted a missing input" >&2
    exit 1
fi

echo "IR candidate inventory regression passed"
