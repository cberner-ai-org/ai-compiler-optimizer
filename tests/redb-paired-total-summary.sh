#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp)"
summary="$(mktemp)"
trap 'rm -f -- "${fixture}" "${summary}"' EXIT

printf '%s\n' $'round\tvariant\telapsed_ns' > "${fixture}"
for round in {1..7}; do
    printf '%s\t%s\t%s\n' "${round}" baseline 100000000000 >> "${fixture}"
    printf '%s\t%s\t%s\n' \
        "${round}" optimized "$(((87 + round) * 1000000000))" \
        >> "${fixture}"
done

"${repo_root}/scripts/summarize-redb-paired-totals.sh" "${fixture}" \
    > "${summary}"
grep --quiet --fixed-strings --line-regexp \
    $'7\t100.000\t91.000\t+9.890\t+9.943\t+9.890\t+7.528\t+12.358' \
    "${summary}"

printf '%s\n' \
    $'round\tvariant\telapsed_ns' \
    $'1\tbaseline\t100' \
    $'1\toptimized\t90' \
    > "${fixture}"
if "${repo_root}/scripts/summarize-redb-paired-totals.sh" "${fixture}" \
    > /dev/null 2>&1; then
    echo "redb paired total summary accepted fewer than two rounds" >&2
    exit 1
fi

printf '%s\n' $'round\tvariant\telapsed_ns' > "${fixture}"
for round in {1..8}; do
    printf '%s\tbaseline\t100000000000\n' "${round}" >> "${fixture}"
    printf '%s\toptimized\t%s\n' \
        "${round}" "$(((87 + round) * 1000000000))" >> "${fixture}"
done
"${repo_root}/scripts/summarize-redb-paired-totals.sh" "${fixture}" > "${summary}"
grep --quiet --fixed-strings --line-regexp \
    $'8\t100.000\t91.500\t+9.290\t+9.358\t+9.293\t+6.909\t+11.807' \
    "${summary}"

echo "redb paired total summary regression passed"
