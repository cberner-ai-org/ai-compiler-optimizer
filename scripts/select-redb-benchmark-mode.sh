#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "redb benchmark mode selector: $*" >&2
    exit 1
}

mode="${ACO_BENCHMARK_MODE:-optimized}"
case "${mode}" in
    optimized)
        expected_pipeline=aco-passes
        ;;
    midpoint)
        expected_pipeline=aco-midpoint-only
        ;;
    slice-comparison)
        expected_pipeline=aco-slice-comparison-only
        ;;
    key-comparisons)
        expected_pipeline=aco-key-comparisons
        ;;
    *)
        fail "ACO_BENCHMARK_MODE must be optimized, midpoint, slice-comparison, or key-comparisons"
        ;;
esac

share_root="${ACO_BENCHMARK_SHARE_ROOT:-/usr/local/share/ai-compiler-optimizer}"
binary_root="${ACO_BENCHMARK_BINARY_ROOT:-/usr/local/bin}"
provenance="${share_root}/benchmark-provenance-${mode}.tsv"
baseline="${binary_root}/redb-benchmark-baseline"
candidate="${binary_root}/redb-benchmark-${mode}"
monotonic_clock="${binary_root}/aco-monotonic-clock"
comparison_runner="${ACO_COMPARISON_RUNNER:-${binary_root}/compare-redb-benchmarks}"

[[ -x "${baseline}" ]] || fail "missing baseline benchmark: ${baseline}"
[[ -x "${candidate}" ]] || fail "missing ${mode} benchmark: ${candidate}"
[[ -x "${monotonic_clock}" ]] || fail "missing monotonic clock: ${monotonic_clock}"
[[ -x "${comparison_runner}" ]] || fail "missing comparison runner: ${comparison_runner}"
[[ -s "${provenance}" ]] || fail "missing ${mode} provenance: ${provenance}"

manifest_value() {
    local key="$1"
    awk -F '\t' -v key="${key}" '
        $1 == key { value = $2; matches++ }
        END {
            if (matches != 1)
                exit 1
            print value
        }
    ' "${provenance}"
}

manifest_mode="$(manifest_value benchmark_candidate_variant)" \
    || fail "provenance has no unique candidate variant"
[[ "${manifest_mode}" == "${mode}" ]] \
    || fail "provenance candidate does not match selected mode"
manifest_pipeline="$(manifest_value optimizer_pipeline)" \
    || fail "provenance has no unique optimizer pipeline"
[[ "${manifest_pipeline}" == "${expected_pipeline}" ]] \
    || fail "provenance pipeline does not match selected mode"
expected_selector_sha256="$(manifest_value benchmark_mode_selector_sha256)" \
    || fail "provenance has no unique mode-selector hash"
actual_selector_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
[[ "${actual_selector_sha256}" == "${expected_selector_sha256}" ]] \
    || fail "mode selector does not match the provenance manifest"

export ACO_BENCHMARK_PROVENANCE="${provenance}"
export ACO_BASELINE_BENCHMARK="${baseline}"
export ACO_OPTIMIZED_BENCHMARK="${candidate}"
export ACO_MONOTONIC_CLOCK="${monotonic_clock}"
export ACO_BENCHMARK_CANDIDATE_LABEL="${mode}"
exec "${comparison_runner}"
