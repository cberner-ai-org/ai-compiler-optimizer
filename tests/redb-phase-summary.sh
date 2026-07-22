#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
summarizer="${repo_root}/scripts/summarize-redb-phases.sh"
fixture="$(mktemp)"
summary="$(mktemp)"
trap 'rm -f -- "${fixture}" "${summary}"' EXIT

printf 'round\tvariant\tphase\toccurrence\telapsed_ms\n' > "${fixture}"
for round in {1..7}; do
    printf '%d\tbaseline\tRandom read 1000000 items\t1\t100\n' "${round}" >> "${fixture}"
    printf '%d\toptimized\tRandom read 1000000 items\t1\t%d\n' "${round}" "$((87 + round))" >> "${fixture}"
    printf '%d\tbaseline\tRandom read 1000000 items\t2\t200\n' "${round}" >> "${fixture}"
    printf '%d\toptimized\tRandom read 1000000 items\t2\t180\n' "${round}" >> "${fixture}"
    printf '%d\tbaseline\tlen()\t1\t0\n' "${round}" >> "${fixture}"
    printf '%d\toptimized\tlen()\t1\t0\n' "${round}" >> "${fixture}"
done
"${summarizer}" "${fixture}" > "${summary}"
grep --quiet --fixed-strings \
    $'Random read 1000000 items\t1\t7\t100.000\t91.000\t+9.890\t+9.943\t+9.890\t+7.528\t+12.358\t' "${summary}"
grep --quiet --fixed-strings --line-regexp \
    $'Random read 1000000 items\t2\t7\t200.000\t180.000\t+11.111\t+11.111\t+11.111\t+11.111\t+11.111\t+11.111\t+11.111' "${summary}"
grep --quiet --fixed-strings --line-regexp \
    $'len()\t1\t7\t0.000\t0.000\t+0.000\t+0.000\t+0.000\t+0.000\t+0.000\t+0.000\t+0.000' "${summary}"

for retained_directory in \
    docs/optimizations/data/redb-slice-reach-2026-07-21 \
    results/three-way-compare-2026-07-21-seven-pair-physical-cores; do
    "${summarizer}" \
        "${repo_root}/${retained_directory}/phases.tsv" \
        > "${summary}"
    cmp \
        "${repo_root}/${retained_directory}/phase-summary.tsv" \
        "${summary}"
done

expect_rejection() {
    local description="$1"
    if "${summarizer}" "${fixture}" > /dev/null 2>&1; then
        echo "redb phase summary accepted ${description}" >&2
        exit 1
    fi
}
printf '%s\n' $'round\tvariant\tphase\toccurrence\telapsed_ms' \
    $'1\tbaseline\tread\t1\t100' $'1\toptimized\tread\t1\t90' \
    $'2\tbaseline\tread\t1\t100' > "${fixture}"
expect_rejection "an incomplete pair"
printf '%s\n' $'round\tvariant\tphase\toccurrence\telapsed_ms' \
    $'1\tbaseline\tread\t1\t100' $'1\tbaseline\tread\t1\t100' \
    $'1\toptimized\tread\t1\t90' $'2\tbaseline\tread\t1\t100' \
    $'2\toptimized\tread\t1\t90' > "${fixture}"
expect_rejection "a duplicate sample"
printf '%s\n' $'round\tvariant\tphase\toccurrence\telapsed_ms' \
    $'1\tbaseline\tread\t1\t1' $'1\toptimized\tread\t1\t0' \
    $'2\tbaseline\tread\t1\t1' $'2\toptimized\tread\t1\t0' > "${fixture}"
expect_rejection "a one-sided zero-duration pair"
printf '%s\n' $'round\tvariant\tphase\toccurrence\telapsed_ms' \
    $'1\tbaseline\tread\t1\t0' $'1\toptimized\tread\t1\t0' \
    $'2\tbaseline\tread\t1\t2' $'2\toptimized\tread\t1\t1' > "${fixture}"
if "${summarizer}" "${fixture}" > /dev/null 2> "${summary}"; then
    echo "redb phase summary accepted mixed zero-duration and measurable pairs" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'mixed zero-duration and measurable pairs for phase read occurrence 1' \
    "${summary}"
echo "redb phase summary regression passed"
