#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp)"
summary="$(mktemp)"
trap 'rm -f -- "${fixture}" "${summary}"' EXIT

printf '%s\n' \
    $'variant\tbuild_elapsed_ms\tbinary_size_bytes' \
    $'baseline\t1000\t2000' \
    $'midpoint\t1100\t1990' \
    $'slice-comparison\t900\t2020' \
    $'key-comparisons\t1050\t2010' \
    $'optimized\t950\t2030' \
    > "${fixture}"

"${repo_root}/scripts/summarize-redb-build-metrics.sh" "${fixture}" \
    > "${summary}"
grep --quiet --fixed-strings --line-regexp \
    $'midpoint\t1100\t+10.000\t1990\t-10\t-0.500' \
    "${summary}"
grep --quiet --fixed-strings --line-regexp \
    $'slice-comparison\t900\t-10.000\t2020\t+20\t+1.000' \
    "${summary}"

printf '%s\n' \
    $'variant\tbuild_elapsed_ms\tbinary_size_bytes' \
    $'baseline\t1000\t2000' \
    $'midpoint\t1100\t1990' \
    $'slice-comparison\t900\t2020' \
    $'key-comparisons\t1050\t2010' \
    > "${fixture}"
if "${repo_root}/scripts/summarize-redb-build-metrics.sh" "${fixture}" \
    > /dev/null 2>&1; then
    echo "redb build metrics summary accepted a missing optimized row" >&2
    exit 1
fi

printf '%s\n' \
    $'variant\tbuild_elapsed_ms\tbinary_size_bytes' \
    $'baseline\t1000\t2000' \
    $'midpoint\t1100\t1990' \
    $'slice-comparison\t900\t2020' \
    $'key-comparison\t1050\t2010' \
    $'optimized\t950\t2030' \
    > "${fixture}"
if "${repo_root}/scripts/summarize-redb-build-metrics.sh" "${fixture}" \
    > /dev/null 2>&1; then
    echo "redb build metrics summary accepted an unknown variant" >&2
    exit 1
fi

echo "redb build metrics regression passed"
