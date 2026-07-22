#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "redb hot slice reach: $*" >&2
    exit 1
}

(( $# == 1 )) || fail "usage: verify-redb-hot-slice-reach TRACE"
trace="$1"
[[ -f "${trace}" ]] || fail "missing trace: ${trace}"

rewrite_prefix='aco-keyhole: transformed [1-9][0-9]* slice compare\(s\), [0-9]+ generic memcmp call\(s\), and [0-9]+ ordered midpoint\(s\) in '

grep --quiet --extended-regexp \
    "${rewrite_prefix}.*12LeafAccessor8positionRShE.*14redb_benchmark$" \
    "${trace}" \
    || fail "missing byte-slice LeafAccessor::position rewrite"

grep --quiet --extended-regexp \
    "${rewrite_prefix}.*14BranchAccessor.*13child_for_keyRShE.*14redb_benchmark$" \
    "${trace}" \
    || fail "missing byte-slice BranchAccessor::child_for_key rewrite"

echo "redb hot slice reach: both byte-slice search functions transformed"
