#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf -- "${fixture_root}"' EXIT

fake_benchmark="${fixture_root}/fake-redb-benchmark"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'variant="${0##*-}"' \
    'printf "%s\n" "${variant}" >> "${ACO_TEST_ORDER_FILE}"' \
    'sleep 0.02' \
    'printf "redb: Fixture phase in %sms\n" "$([[ "${variant}" == baseline ]] && echo 10 || echo 8)"' \
    'printf "redb: Repeated phase in 4ms\n"' \
    'printf "redb: Repeated phase in 5ms, with suffix\n"' \
    > "${fake_benchmark}"
chmod 0755 "${fake_benchmark}"
cp "${fake_benchmark}" "${fixture_root}/redb-benchmark-baseline"
cp "${fake_benchmark}" "${fixture_root}/redb-benchmark-optimized"

baseline_sha256="$(sha256sum "${fixture_root}/redb-benchmark-baseline" | awk '{print $1}')"
optimized_sha256="$(sha256sum "${fixture_root}/redb-benchmark-optimized" | awk '{print $1}')"
clock_state="${fixture_root}/clock-state"
fake_clock="${fixture_root}/monotonic-clock"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ -n "${ACO_TEST_TIMING_EVENTS:-}" ]]; then' \
    '    printf "clock\n" >> "${ACO_TEST_TIMING_EVENTS}"' \
    'fi' \
    'if [[ -n "${ACO_TEST_PHASE_COUNT_LOG:-}" ]]; then' \
    '    wc -l < "${ACO_BENCHMARK_PHASE_RESULTS}" >> "${ACO_TEST_PHASE_COUNT_LOG}"' \
    'fi' \
    'value="$(head -n 1 "${ACO_TEST_CLOCK_STATE}")"' \
    'tail -n +2 "${ACO_TEST_CLOCK_STATE}" > "${ACO_TEST_CLOCK_STATE}.next"' \
    'mv "${ACO_TEST_CLOCK_STATE}.next" "${ACO_TEST_CLOCK_STATE}"' \
    'printf "%s\n" "${value}"' \
    > "${fake_clock}"
chmod 0755 "${fake_clock}"
printf '100\n200\n300\n400\n500\n600\n700\n800\n' > "${clock_state}"

real_mktemp="$(command -v mktemp)"
mkdir "${fixture_root}/bin"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "mktemp\n" >> "${ACO_TEST_TIMING_EVENTS}"' \
    "exec ${real_mktemp} \"\$@\"" \
    > "${fixture_root}/bin/mktemp"
chmod 0755 "${fixture_root}/bin/mktemp"

clock_sha256="$(sha256sum "${fake_clock}" | awk '{print $1}')"
runner_sha256="$(sha256sum "${repo_root}/scripts/compare-redb-benchmarks.sh" | awk '{print $1}')"
provenance_file="${fixture_root}/benchmark-provenance.tsv"
printf '%s\t%s\n' \
    manifest_format aco-benchmark-provenance-v1 \
    baseline_benchmark_sha256 "${baseline_sha256}" \
    optimized_benchmark_sha256 "${optimized_sha256}" \
    monotonic_clock_sha256 "${clock_sha256}" \
    comparison_runner_sha256 "${runner_sha256}" \
    > "${provenance_file}"

cpuinfo_file="${fixture_root}/cpuinfo"
printf '%s\n' \
    'CPU implementer : 0x41' \
    'CPU part : 0xd0c' \
    > "${cpuinfo_file}"

results_file="${fixture_root}/results.tsv"
phase_results_file="${fixture_root}/phase-results.tsv"
order_file="${fixture_root}/order"
output_file="${fixture_root}/output"
timing_events="${fixture_root}/timing-events"
phase_count_log="${fixture_root}/phase-count-log"
ACO_BASELINE_BENCHMARK="${fixture_root}/redb-benchmark-baseline" \
ACO_OPTIMIZED_BENCHMARK="${fixture_root}/redb-benchmark-optimized" \
ACO_BENCHMARK_RUNS=2 \
ACO_BENCHMARK_RESULTS="${results_file}" \
ACO_BENCHMARK_PHASE_RESULTS="${phase_results_file}" \
ACO_BENCHMARK_PROVENANCE="${provenance_file}" \
ACO_MONOTONIC_CLOCK="${fake_clock}" \
ACO_CPUINFO="${cpuinfo_file}" \
ACO_TEST_CLOCK_STATE="${clock_state}" \
ACO_TEST_ORDER_FILE="${order_file}" \
ACO_TEST_TIMING_EVENTS="${timing_events}" \
ACO_TEST_PHASE_COUNT_LOG="${phase_count_log}" \
PATH="${fixture_root}/bin:${PATH}" \
    "${repo_root}/scripts/compare-redb-benchmarks.sh" > "${output_file}"

expected_timing_events=$'mktemp\nclock\nclock\nmktemp\nclock\nclock\nmktemp\nclock\nclock\nmktemp\nclock\nclock'
[[ "$(<"${timing_events}")" == "${expected_timing_events}" ]] || {
    echo "benchmark timing did not bracket each process after output setup" >&2
    exit 1
}
expected_phase_counts=$'1\n1\n4\n4\n7\n7\n10\n10'
[[ "$(<"${phase_count_log}")" == "${expected_phase_counts}" ]] || {
    echo "benchmark finish timestamp included phase extraction" >&2
    exit 1
}

expected_order=$'baseline\noptimized\noptimized\nbaseline'
actual_order="$(<"${order_file}")"
[[ "${actual_order}" == "${expected_order}" ]] || {
    echo "benchmark variants did not alternate by round" >&2
    printf 'expected:\n%s\nactual:\n%s\n' "${expected_order}" "${actual_order}" >&2
    exit 1
}

[[ "$(wc -l < "${results_file}")" == 5 ]] \
    || { echo "comparison did not record two complete result pairs" >&2; exit 1; }
grep --quiet --fixed-strings $'round\tbaseline_s\toptimized_s\toptimized_speedup_percent' \
    "${output_file}"
grep --quiet --fixed-strings $'mean\t' "${output_file}"
grep --quiet --fixed-strings \
    $'phase\toccurrence\tbaseline_mean_ms\toptimized_mean_ms\toptimized_speedup_percent' \
    "${output_file}"
grep --quiet --fixed-strings $'Fixture phase\t1\t10.0\t8.0\t+25.00%' \
    "${output_file}"
grep --quiet --fixed-strings $'Repeated phase\t2\t5.0\t5.0\t+0.00%' \
    "${output_file}"
[[ "$(wc -l < "${phase_results_file}")" == 13 ]] \
    || { echo "comparison did not record every phase sample" >&2; exit 1; }
grep --quiet --fixed-strings 'effective CPU list:' "${output_file}"
grep --quiet --fixed-strings 'effective CPU count:' "${output_file}"
grep --quiet --fixed-strings 'CPU vendor: 0x41' "${output_file}"
grep --quiet --fixed-strings 'CPU model: 0xd0c' "${output_file}"
grep --quiet --fixed-strings 'timing clock: clock_gettime(CLOCK_MONOTONIC)' "${output_file}"
grep --quiet --fixed-strings \
    "comparison runner sha256: ${runner_sha256}" \
    "${output_file}"

printf 'processor : 0\n' > "${cpuinfo_file}"
printf '900\n1000\n1100\n1200\n' > "${clock_state}"
: > "${order_file}"
fallback_output="${fixture_root}/fallback-output"
ACO_BASELINE_BENCHMARK="${fixture_root}/redb-benchmark-baseline" \
ACO_OPTIMIZED_BENCHMARK="${fixture_root}/redb-benchmark-optimized" \
ACO_BENCHMARK_RUNS=1 \
ACO_BENCHMARK_RESULTS="${fixture_root}/fallback-results.tsv" \
ACO_BENCHMARK_PROVENANCE="${provenance_file}" \
ACO_MONOTONIC_CLOCK="${fake_clock}" \
ACO_CPUINFO="${cpuinfo_file}" \
ACO_TEST_CLOCK_STATE="${clock_state}" \
ACO_TEST_ORDER_FILE="${order_file}" \
    "${repo_root}/scripts/compare-redb-benchmarks.sh" > "${fallback_output}"
grep --quiet --fixed-strings 'CPU vendor: unknown' "${fallback_output}"
grep --quiet --fixed-strings 'CPU model: unknown' "${fallback_output}"

mismatched_provenance="${fixture_root}/mismatched-provenance.tsv"
sed \
    's/^comparison_runner_sha256\t.*/comparison_runner_sha256\tmismatch/' \
    "${provenance_file}" \
    > "${mismatched_provenance}"
if ACO_BASELINE_BENCHMARK="${fixture_root}/redb-benchmark-baseline" \
    ACO_OPTIMIZED_BENCHMARK="${fixture_root}/redb-benchmark-optimized" \
    ACO_BENCHMARK_PROVENANCE="${mismatched_provenance}" \
    ACO_BENCHMARK_RUNS=1 \
    ACO_MONOTONIC_CLOCK="${fake_clock}" \
    ACO_TEST_CLOCK_STATE="${clock_state}" \
    ACO_TEST_ORDER_FILE="${order_file}" \
    "${repo_root}/scripts/compare-redb-benchmarks.sh" \
    > "${fixture_root}/runner-mismatch.log" 2>&1; then
    echo "comparison accepted a runner absent from provenance" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'comparison runner does not match the provenance manifest' \
    "${fixture_root}/runner-mismatch.log"

if ACO_BASELINE_BENCHMARK="${fixture_root}/redb-benchmark-baseline" \
    ACO_OPTIMIZED_BENCHMARK="${fixture_root}/redb-benchmark-optimized" \
    ACO_BENCHMARK_PROVENANCE="${provenance_file}" \
    ACO_BENCHMARK_RUNS=0 \
    ACO_MONOTONIC_CLOCK="${fake_clock}" \
    ACO_TEST_CLOCK_STATE="${clock_state}" \
    "${repo_root}/scripts/compare-redb-benchmarks.sh" \
    > "${fixture_root}/invalid.log" 2>&1; then
    echo "comparison accepted zero benchmark rounds" >&2
    exit 1
fi

printf '100\n100\n' > "${clock_state}"
if ACO_BASELINE_BENCHMARK="${fixture_root}/redb-benchmark-baseline" \
    ACO_OPTIMIZED_BENCHMARK="${fixture_root}/redb-benchmark-optimized" \
    ACO_BENCHMARK_PROVENANCE="${provenance_file}" \
    ACO_BENCHMARK_RUNS=1 \
    ACO_MONOTONIC_CLOCK="${fake_clock}" \
    ACO_TEST_CLOCK_STATE="${clock_state}" \
    ACO_TEST_ORDER_FILE="${order_file}" \
    "${repo_root}/scripts/compare-redb-benchmarks.sh" \
    > "${fixture_root}/non-positive.log" 2>&1; then
    echo "comparison accepted a non-positive monotonic sample" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'produced a non-positive monotonic elapsed sample' \
    "${fixture_root}/non-positive.log"

echo "redb benchmark comparison regression passed"
