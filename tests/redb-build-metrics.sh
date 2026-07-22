#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
summarizer="${repo_root}/scripts/summarize-redb-build-metrics.sh"
fixture="$(mktemp)"
summary="$(mktemp)"
trap 'rm -f -- "${fixture}" "${summary}"' EXIT

printf '%s\n' \
    $'variant\tbuild_elapsed_ms\tbinary_size_bytes' \
    $'baseline\t1000\t2000' \
    $'three-way-compare\t1020\t2005' \
    $'midpoint\t1100\t1990' \
    $'slice-comparison\t900\t2020' \
    $'key-comparisons\t1050\t2010' \
    $'optimized\t950\t2030' \
    > "${fixture}"

"${summarizer}" --schema current-v2 "${fixture}" \
    > "${summary}"
grep --quiet --fixed-strings --line-regexp \
    $'midpoint\t1100\t+10.000\t1990\t-10\t-0.500' \
    "${summary}"
grep --quiet --fixed-strings --line-regexp \
    $'slice-comparison\t900\t-10.000\t2020\t+20\t+1.000' \
    "${summary}"
"${summarizer}" "${fixture}" > /dev/null

for retained_directory in \
    docs/optimizations/data/redb-key-comparisons-2026-07-19 \
    results/default-scmp-2026-07-20 \
    results/pass-ablation-master-2026-07-20; do
    "${summarizer}" \
        "${repo_root}/${retained_directory}/build-metrics.tsv" \
        > "${summary}"
    cmp \
        "${repo_root}/${retained_directory}/build-metrics-summary.tsv" \
        "${summary}"
done

legacy_metrics="${repo_root}/results/default-scmp-2026-07-20/build-metrics.tsv"
if "${summarizer}" --schema current-v2 "${legacy_metrics}" \
    > /dev/null 2>&1; then
    echo "redb build metrics summary accepted legacy-v1 as current-v2" >&2
    exit 1
fi

printf '%s\n' \
    $'variant\tbuild_elapsed_ms\tbinary_size_bytes' \
    $'baseline\t1000\t2000' \
    $'three-way-compare\t1020\t2005' \
    $'midpoint\t1100\t1990' \
    $'slice-comparison\t900\t2020' \
    $'key-comparisons\t1050\t2010' \
    > "${fixture}"
if "${summarizer}" --schema current-v2 "${fixture}" \
    > /dev/null 2>&1; then
    echo "redb build metrics summary accepted a missing optimized row" >&2
    exit 1
fi

printf '%s\n' \
    $'variant\tbuild_elapsed_ms\tbinary_size_bytes' \
    $'baseline\t1000\t2000' \
    $'three-way-compare\t1020\t2005' \
    $'midpoint\t1100\t1990' \
    $'slice-comparison\t900\t2020' \
    $'key-comparison\t1050\t2010' \
    $'optimized\t950\t2030' \
    > "${fixture}"
if "${summarizer}" "${fixture}" \
    > /dev/null 2>&1; then
    echo "redb build metrics summary accepted an unknown variant" >&2
    exit 1
fi

if "${summarizer}" --schema future-v3 "${fixture}" \
    > /dev/null 2>&1; then
    echo "redb build metrics summary accepted an unknown schema" >&2
    exit 1
fi

echo "redb build metrics regression passed"
