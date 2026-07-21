#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
summarizer="${repo_root}/scripts/summarize-redb-subbenchmarks.sh"
fixture="$(mktemp)"
summary="$(mktemp)"
trap 'rm -f -- "${fixture}" "${summary}"' EXIT

emit_measurements() {
    local variant="$1"
    local elapsed="$2"

    printf '[%s] redb: Bulk loaded 5000000 items in %sms\n' "${variant}" "${elapsed}"
    printf '[%s] redb: Wrote 1000 individual items in %sms\n' "${variant}" "${elapsed}"
    printf '[%s] redb: Wrote 100 batches of 1000 items in %sms\n' "${variant}" "${elapsed}"
    printf '[%s] redb: Wrote 50000 individual items in %sms, with nosync\n' "${variant}" "${elapsed}"
    printf '[%s] redb: Random read 1000000 items in %sms\n' "${variant}" "${elapsed}"
    printf '[%s] redb: Random read 1000000 items in %sms\n' "${variant}" "${elapsed}"
    printf '[%s] redb: Random range read 500000 x 10 elements in %sms\n' "${variant}" "${elapsed}"
    printf '[%s] redb: Random range read 500000 x 10 elements in %sms\n' "${variant}" "${elapsed}"
    printf '[%s] redb: Random read (4 threads) 5151000 items in %sms\n' "${variant}" "${elapsed}"
    printf '[%s] redb: Random read (8 threads) 5151000 items in %sms\n' "${variant}" "${elapsed}"
    printf '[%s] redb: Random read (16 threads) 5151000 items in %sms\n' "${variant}" "${elapsed}"
    printf '[%s] redb: Random read (32 threads) 5151000 items in %sms\n' "${variant}" "${elapsed}"
    printf '[%s] redb: Removed 2575500 items in %sms\n' "${variant}" "${elapsed}"
    printf '[%s] redb: Compacted in %sms\n' "${variant}" "${elapsed}"
}

for round in {1..7}; do
    printf '[round %d/7] baseline (custom passes disabled)\n' "${round}" >> "${fixture}"
    emit_measurements baseline 100 >> "${fixture}"
    printf '[round %d/7] optimized (custom passes enabled)\n' "${round}" >> "${fixture}"
    emit_measurements optimized "$((87 + round))" >> "${fixture}"
done

"${summarizer}" "${fixture}" > "${summary}"

expected=$'random_range_reads\t7\t14\t100.000\t91.000\t+9.890\t+9.943\t+9.890\t+7.528\t+12.358\t+5.516\t+14.371'
grep --quiet --fixed-strings --line-regexp "${expected}" "${summary}"
[[ "$(wc -l < "${summary}")" == 13 ]]

: > "${fixture}"
for round in {1..8}; do
    printf '[round %d/8] baseline (custom passes disabled)\n' "${round}" >> "${fixture}"
    emit_measurements baseline 100 >> "${fixture}"
    printf '[round %d/8] optimized (custom passes enabled)\n' "${round}" >> "${fixture}"
    emit_measurements optimized "$((87 + round))" >> "${fixture}"
done
"${summarizer}" "${fixture}" > "${summary}"
expected=$'random_range_reads\t8\t16\t100.000\t91.500\t+9.290\t+9.358\t+9.293\t+6.909\t+11.807\t+5.035\t+13.682'
grep --quiet --fixed-strings --line-regexp "${expected}" "${summary}"

expect_rejection() {
    local description="$1"

    if "${summarizer}" "${fixture}" > /dev/null 2>&1; then
        echo "redb sub-benchmark summary accepted ${description}" >&2
        exit 1
    fi
}

: > "${fixture}"
printf '[round 1/2] baseline (custom passes disabled)\n' >> "${fixture}"
emit_measurements baseline 100 >> "${fixture}"
printf '[round 1/3] optimized (custom passes enabled)\n' >> "${fixture}"
emit_measurements optimized 90 >> "${fixture}"
expect_rejection "conflicting declared round counts"

: > "${fixture}"
for variant in baseline optimized; do
    printf '[round 1/2] %s\n' "${variant}" >> "${fixture}"
    emit_measurements "${variant}" 100 >> "${fixture}"
done
printf '[round 1/2] baseline (duplicate)\n' >> "${fixture}"
emit_measurements baseline 100 >> "${fixture}"
expect_rejection "a duplicate round header"

: > "${fixture}"
for round in 1 3; do
    for variant in baseline optimized; do
        printf '[round %d/3] %s\n' "${round}" "${variant}" >> "${fixture}"
        emit_measurements "${variant}" 100 >> "${fixture}"
    done
done
expect_rejection "a missing round"

echo "redb sub-benchmark summary regression passed"
