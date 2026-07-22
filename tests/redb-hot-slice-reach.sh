#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
verifier="${repo_root}/scripts/verify-redb-hot-slice-reach.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf -- "${fixture_root}"' EXIT

trace="${fixture_root}/slice.trace"
leaf_line='aco-keyhole: transformed 1 slice compare(s), 0 generic memcmp call(s), and 0 ordered midpoint(s) in _RINvMs9_NtNtCsi_4redb10tree_store10btree_baseNtB6_12LeafAccessor8positionRShECs5_14redb_benchmark'
branch_line='aco-keyhole: transformed 1 slice compare(s), 0 generic memcmp call(s), and 1 ordered midpoint(s) in _RINvMse_NtNtCsi_4redb10tree_store10btree_baseINtB6_14BranchAccessorNtNtNtB8_10page_store4base8PageImplE13child_for_keyRShECs5_14redb_benchmark'

printf '%s\n' \
    'aco-keyhole: transformed 4 slice compare(s), 0 generic memcmp call(s), and 0 ordered midpoint(s) in unrelated_library_code' \
    "${leaf_line}" \
    "${branch_line}" \
    > "${trace}"
"${verifier}" "${trace}" > /dev/null

printf '%s\n' "${branch_line}" > "${trace}"
if "${verifier}" "${trace}" > /dev/null 2> "${fixture_root}/missing-leaf.log"; then
    echo "redb hot slice reach verifier accepted a missing leaf rewrite" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'missing byte-slice LeafAccessor::position rewrite' \
    "${fixture_root}/missing-leaf.log"

printf '%s\n' "${leaf_line}" > "${trace}"
if "${verifier}" "${trace}" > /dev/null 2> "${fixture_root}/missing-branch.log"; then
    echo "redb hot slice reach verifier accepted a missing branch rewrite" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'missing byte-slice BranchAccessor::child_for_key rewrite' \
    "${fixture_root}/missing-branch.log"

printf '%s\n' \
    'aco-keyhole: transformed 1 slice compare(s), 0 generic memcmp call(s), and 0 ordered midpoint(s) in _RINvMs9_12LeafAccessor8positionReECs5_14redb_benchmark' \
    "${branch_line}" \
    > "${trace}"
if "${verifier}" "${trace}" > /dev/null 2> "${fixture_root}/wrong-key-type.log"; then
    echo "redb hot slice reach verifier accepted a non-byte-slice leaf specialization" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'missing byte-slice LeafAccessor::position rewrite' \
    "${fixture_root}/wrong-key-type.log"

printf '%s\n' \
    'aco-keyhole: transformed 0 slice compare(s), 1 generic memcmp call(s), and 0 ordered midpoint(s) in _RINvMs9_12LeafAccessor8positionRShECs5_14redb_benchmark' \
    "${branch_line}" \
    > "${trace}"
if "${verifier}" "${trace}" > /dev/null 2> "${fixture_root}/zero-leaf.log"; then
    echo "redb hot slice reach verifier accepted a zero-count leaf trace" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'missing byte-slice LeafAccessor::position rewrite' \
    "${fixture_root}/zero-leaf.log"

echo "redb hot slice reach regression passed"
