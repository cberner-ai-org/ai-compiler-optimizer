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

rewrite_count="$(awk '
    /aco-three-way-compare: transformed [1-9][0-9]* switch/ {
        rewrites++
        next
    }
    /aco-keyhole: transformed [1-9][0-9]* slice compare/ ||
    /aco-keyhole: transformed [0-9]+ slice compare\(s\), [1-9][0-9]* generic memcmp/ ||
    /aco-keyhole: transformed [0-9]+ slice compare\(s\), [0-9]+ generic memcmp call\(s\), and [1-9][0-9]* ordered midpoint/ {
        rewrites++
    }
    END { print rewrites + 0 }
' "${optimized_trace}")"
(( rewrite_count >= 1 )) || fail "optimized transformation count is not positive"

printf 'redb optimizer trace boundary: baseline excluded; optimized transforming traces: %s\n' \
    "${rewrite_count}"
