#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "redb optimizer trace boundary: $*" >&2
    exit 1
}

baseline_trace="${1:?usage: verify-redb-variant-traces BASELINE_TRACE OPTIMIZED_TRACE}"
optimized_trace="${2:?usage: verify-redb-variant-traces BASELINE_TRACE OPTIMIZED_TRACE}"

[[ -f "${baseline_trace}" ]] || fail "missing baseline trace: ${baseline_trace}"
[[ -f "${optimized_trace}" ]] || fail "missing optimized trace: ${optimized_trace}"

if grep --quiet --extended-regexp \
    'aco-(keyhole|three-way-compare):' \
    "${baseline_trace}"; then
    fail "baseline unexpectedly scheduled the ACO pipeline"
fi

if grep --quiet --fixed-strings 'aco-keyhole:' "${optimized_trace}"; then
    fail "default optimized unexpectedly scheduled disabled keyhole rewrites"
fi

rewrite_count="$(awk '
    /aco-three-way-compare: transformed [1-9][0-9]* switch/ {
        rewrites++
    }
    END { print rewrites + 0 }
' "${optimized_trace}")"
(( rewrite_count >= 1 )) || fail "optimized signed-switch transformation count is not positive"

printf 'redb optimizer trace boundary: baseline excluded; optimized signed-switch traces: %s\n' \
    "${rewrite_count}"
