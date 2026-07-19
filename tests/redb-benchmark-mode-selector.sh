#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf -- "${fixture_root}"' EXIT
mkdir -p "${fixture_root}/bin" "${fixture_root}/share"

selector="${repo_root}/scripts/select-redb-benchmark-mode.sh"
selector_sha256="$(sha256sum "${selector}" | awk '{print $1}')"
for mode in optimized midpoint slice-comparison key-comparisons; do
    case "${mode}" in
        optimized)
            pipeline=aco-passes
            ;;
        midpoint)
            pipeline=aco-midpoint-only
            ;;
        slice-comparison)
            pipeline=aco-slice-comparison-only
            ;;
        key-comparisons)
            pipeline=aco-key-comparisons
            ;;
    esac
    printf '#!/usr/bin/env bash\nexit 0\n' \
        > "${fixture_root}/bin/redb-benchmark-${mode}"
    chmod 0755 "${fixture_root}/bin/redb-benchmark-${mode}"
    printf '%s\t%s\n' \
        benchmark_candidate_variant "${mode}" \
        optimizer_pipeline "${pipeline}" \
        benchmark_mode_selector_sha256 "${selector_sha256}" \
        > "${fixture_root}/share/benchmark-provenance-${mode}.tsv"
done
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n%s\n%s\n" "${ACO_OPTIMIZED_BENCHMARK}" "${ACO_BENCHMARK_PROVENANCE}" "${ACO_BENCHMARK_CANDIDATE_LABEL}"' \
    > "${fixture_root}/bin/compare-redb-benchmarks"
chmod 0755 "${fixture_root}/bin/compare-redb-benchmarks"

output="$(
    ACO_BENCHMARK_MODE=midpoint \
    ACO_BENCHMARK_SHARE_ROOT="${fixture_root}/share" \
    ACO_BENCHMARK_BINARY_ROOT="${fixture_root}/bin" \
        "${selector}"
)"
expected="${fixture_root}/bin/redb-benchmark-midpoint
${fixture_root}/share/benchmark-provenance-midpoint.tsv
midpoint"
[[ "${output}" == "${expected}" ]]

sed --in-place \
    's/^optimizer_pipeline\t.*/optimizer_pipeline\taco-passes/' \
    "${fixture_root}/share/benchmark-provenance-midpoint.tsv"
if ACO_BENCHMARK_MODE=midpoint \
    ACO_BENCHMARK_SHARE_ROOT="${fixture_root}/share" \
    ACO_BENCHMARK_BINARY_ROOT="${fixture_root}/bin" \
        "${selector}" > "${fixture_root}/pipeline-mismatch.log" 2>&1; then
    echo "benchmark mode selector accepted a mismatched pipeline" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'provenance pipeline does not match selected mode' \
    "${fixture_root}/pipeline-mismatch.log"

sed --in-place '/^optimizer_pipeline\t/d' \
    "${fixture_root}/share/benchmark-provenance-slice-comparison.tsv"
if ACO_BENCHMARK_MODE=slice-comparison \
    ACO_BENCHMARK_SHARE_ROOT="${fixture_root}/share" \
    ACO_BENCHMARK_BINARY_ROOT="${fixture_root}/bin" \
        "${selector}" > "${fixture_root}/missing-pipeline.log" 2>&1; then
    echo "benchmark mode selector accepted a missing pipeline" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'provenance has no unique optimizer pipeline' \
    "${fixture_root}/missing-pipeline.log"

if ACO_BENCHMARK_MODE=unknown \
    ACO_BENCHMARK_SHARE_ROOT="${fixture_root}/share" \
    ACO_BENCHMARK_BINARY_ROOT="${fixture_root}/bin" \
        "${selector}" > /dev/null 2>&1; then
    echo "benchmark mode selector accepted an unknown mode" >&2
    exit 1
fi

echo "redb benchmark mode selector regression passed"
