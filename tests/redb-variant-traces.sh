#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
verifier="${repo_root}/scripts/verify-redb-variant-traces.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf -- "${fixture_root}"' EXIT

baseline_trace="${fixture_root}/baseline.trace"
optimized_trace="${fixture_root}/optimized.trace"
printf 'Finished release profile\n' > "${baseline_trace}"
printf '%s\n' \
    'aco-keyhole: transformed 1 slice compare(s), 0 generic memcmp call(s), and 0 ordered midpoint(s) in redb_probe' \
    > "${optimized_trace}"
if "${verifier}" "${baseline_trace}" "${optimized_trace}" \
    > "${fixture_root}/slice-enabled.log" 2>&1; then
    echo "redb trace verifier accepted slice comparison in the default pipeline" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'default optimized unexpectedly scheduled disabled keyhole rewrites' \
    "${fixture_root}/slice-enabled.log"

printf '%s\n' \
    'aco-keyhole: transformed 0 slice compare(s), 0 generic memcmp call(s), and 2 ordered midpoint(s) in redb_probe' \
    > "${optimized_trace}"
if "${verifier}" "${baseline_trace}" "${optimized_trace}" \
    > "${fixture_root}/midpoint-enabled.log" 2>&1; then
    echo "redb trace verifier accepted midpoint narrowing in the default pipeline" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'default optimized unexpectedly scheduled disabled keyhole rewrites' \
    "${fixture_root}/midpoint-enabled.log"

printf 'aco-three-way-compare: transformed 2 switch(es) in redb_probe\n' \
    > "${optimized_trace}"
"${verifier}" "${baseline_trace}" "${optimized_trace}" > /dev/null

printf '%s\n' \
    'aco-three-way-compare: transformed 2 switch(es) in redb_probe' \
    'aco-keyhole: transformed 1 slice compare(s), 0 generic memcmp call(s), and 0 ordered midpoint(s) in redb_probe' \
    > "${optimized_trace}"
if "${verifier}" "${baseline_trace}" "${optimized_trace}" \
    > "${fixture_root}/mixed-pipeline.log" 2>&1; then
    echo "redb trace verifier accepted keyhole rewrites alongside the default pass" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'default optimized unexpectedly scheduled disabled keyhole rewrites' \
    "${fixture_root}/mixed-pipeline.log"

printf 'aco-three-way-compare: transformed 2 switch(es) in redb_probe\n' \
    > "${optimized_trace}"

printf 'aco-keyhole: ran on contaminated_baseline\n' >> "${baseline_trace}"
if "${verifier}" "${baseline_trace}" "${optimized_trace}" \
    > "${fixture_root}/baseline-contamination.log" 2>&1; then
    echo "redb trace verifier accepted a baseline ACO trace" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'baseline unexpectedly scheduled the ACO pipeline' \
    "${fixture_root}/baseline-contamination.log"

printf 'Finished release profile\n' > "${baseline_trace}"
printf 'aco-three-way-compare: ran on redb_probe\n' > "${optimized_trace}"
if "${verifier}" "${baseline_trace}" "${optimized_trace}" \
    > "${fixture_root}/missing-transformation.log" 2>&1; then
    echo "redb trace verifier accepted an optimized no-op trace" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'optimized signed-switch transformation count is not positive' \
    "${fixture_root}/missing-transformation.log"

printf '%s\n' \
    'aco-keyhole: transformed 0 slice compare(s), 0 generic memcmp call(s), and 0 ordered midpoint(s) in redb_probe' \
    > "${optimized_trace}"
if "${verifier}" "${baseline_trace}" "${optimized_trace}" \
    > "${fixture_root}/zero-transformations.log" 2>&1; then
    echo "redb trace verifier accepted an all-zero trace" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'default optimized unexpectedly scheduled disabled keyhole rewrites' \
    "${fixture_root}/zero-transformations.log"

echo "redb optimizer trace boundary regression passed"
