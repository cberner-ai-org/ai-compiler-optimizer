#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "redb benchmark comparison: $*" >&2
    exit 1
}

runs="${ACO_BENCHMARK_RUNS:-1}"
[[ "${runs}" =~ ^[1-9][0-9]*$ ]] \
    || fail "ACO_BENCHMARK_RUNS must be a positive integer"

baseline_binary="${ACO_BASELINE_BENCHMARK:-/usr/local/bin/redb-benchmark-baseline}"
optimized_binary="${ACO_OPTIMIZED_BENCHMARK:-/usr/local/bin/redb-benchmark-optimized}"
provenance_file="${ACO_BENCHMARK_PROVENANCE:-/usr/local/share/ai-compiler-optimizer/benchmark-provenance.tsv}"
[[ -x "${baseline_binary}" ]] || fail "missing baseline executable: ${baseline_binary}"
[[ -x "${optimized_binary}" ]] || fail "missing optimized executable: ${optimized_binary}"
[[ -s "${provenance_file}" ]] || fail "missing provenance manifest: ${provenance_file}"

hash_file() {
    sha256sum "$1" | awk '{print $1}'
}

manifest_value() {
    local key="$1"
    awk -F '\t' -v key="${key}" '
        $1 == key { value = $2; matches++ }
        END {
            if (matches != 1)
                exit 1
            print value
        }
    ' "${provenance_file}"
}

baseline_sha256="$(hash_file "${baseline_binary}")"
optimized_sha256="$(hash_file "${optimized_binary}")"
expected_baseline_sha256="$(manifest_value baseline_benchmark_sha256)" \
    || fail "provenance manifest has no unique baseline benchmark hash"
expected_optimized_sha256="$(manifest_value optimized_benchmark_sha256)" \
    || fail "provenance manifest has no unique optimized benchmark hash"
monotonic_clock="${ACO_MONOTONIC_CLOCK:-/usr/local/bin/aco-monotonic-clock}"
[[ -x "${monotonic_clock}" ]] \
    || fail "monotonic clock is not executable: ${monotonic_clock}"
monotonic_clock_sha256="$(hash_file "${monotonic_clock}")"
expected_monotonic_clock_sha256="$(manifest_value monotonic_clock_sha256)" \
    || fail "provenance manifest has no unique monotonic clock hash"
comparison_runner_sha256="$(hash_file "${BASH_SOURCE[0]}")"
expected_comparison_runner_sha256="$(manifest_value comparison_runner_sha256)" \
    || fail "provenance manifest has no unique comparison runner hash"
[[ "${baseline_sha256}" == "${expected_baseline_sha256}" ]] \
    || fail "baseline executable does not match the provenance manifest"
[[ "${optimized_sha256}" == "${expected_optimized_sha256}" ]] \
    || fail "optimized executable does not match the provenance manifest"
[[ "${monotonic_clock_sha256}" == "${expected_monotonic_clock_sha256}" ]] \
    || fail "monotonic clock does not match the provenance manifest"
[[ "${comparison_runner_sha256}" == "${expected_comparison_runner_sha256}" ]] \
    || fail "comparison runner does not match the provenance manifest"

count_cpu_list() {
    local cpu_list="$1"
    local cpu_range
    local range_start
    local range_end
    local total=0
    local -a cpu_ranges

    IFS=',' read -r -a cpu_ranges <<< "${cpu_list}"
    (( ${#cpu_ranges[@]} > 0 )) || fail "effective CPU list is empty"
    for cpu_range in "${cpu_ranges[@]}"; do
        if [[ "${cpu_range}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            range_start="${BASH_REMATCH[1]}"
            range_end="${BASH_REMATCH[2]}"
            (( range_end >= range_start )) \
                || fail "invalid effective CPU range: ${cpu_range}"
            total=$((total + range_end - range_start + 1))
        elif [[ "${cpu_range}" =~ ^[0-9]+$ ]]; then
            total=$((total + 1))
        else
            fail "invalid effective CPU list: ${cpu_list}"
        fi
    done
    (( total > 0 )) || fail "effective CPU count is not positive"
    printf '%s\n' "${total}"
}

effective_cpu_list="$({
    while read -r field value _; do
        if [[ "${field}" == Cpus_allowed_list: ]]; then
            printf '%s\n' "${value}"
            break
        fi
    done < /proc/self/status
})"
[[ -n "${effective_cpu_list}" ]] \
    || fail "could not read effective CPU affinity from /proc/self/status"
effective_cpu_count="$(count_cpu_list "${effective_cpu_list}")"
online_cpu_count="$(getconf _NPROCESSORS_ONLN)"
[[ "${online_cpu_count}" =~ ^[1-9][0-9]*$ ]] \
    || fail "online CPU count is not a positive integer"

monotonic_now_ns() {
    local value

    value="$("${monotonic_clock}")" \
        || fail "monotonic clock command failed"

    [[ "${value}" =~ ^[0-9]+$ ]] \
        || fail "monotonic clock returned a non-integer value: ${value}"
    printf '%s\n' "${value}"
}

temporary_results=false
if [[ -n "${ACO_BENCHMARK_RESULTS:-}" ]]; then
    results_file="${ACO_BENCHMARK_RESULTS}"
else
    results_file="$(mktemp)"
    temporary_results=true
fi
trap 'if [[ "${temporary_results}" == true ]]; then rm -f -- "${results_file}"; fi' EXIT
: > "${results_file}"
printf 'round\tvariant\telapsed_ns\n' >> "${results_file}"

echo "redb baseline/optimized comparison"
printf 'runs: %s\n' "${runs}"
printf 'machine: %s\n' "$(uname -srmo)"
printf 'online CPU count: %s\n' "${online_cpu_count}"
printf 'effective CPU list: %s\n' "${effective_cpu_list}"
printf 'effective CPU count: %s\n' "${effective_cpu_count}"
printf 'timing clock: clock_gettime(CLOCK_MONOTONIC)\n'
printf 'timing clock sha256: %s\n' "${monotonic_clock_sha256}"
printf 'comparison runner sha256: %s\n' "${comparison_runner_sha256}"
printf 'provenance manifest sha256: %s\n' "$(hash_file "${provenance_file}")"
while IFS=$'\t' read -r key value extra; do
    [[ -n "${key}" && -n "${value}" && -z "${extra}" ]] \
        || fail "invalid provenance manifest row"
    printf 'provenance %s: %s\n' "${key}" "${value}"
done < "${provenance_file}"
printf 'baseline sha256: %s\n' "${baseline_sha256}"
printf 'optimized sha256: %s\n' "${optimized_sha256}"

run_variant() {
    local round="$1"
    local variant="$2"
    local binary
    local started_ns
    local finished_ns
    local elapsed_ns
    local -a pipeline_status

    case "${variant}" in
        baseline)
            binary="${baseline_binary}"
            ;;
        optimized)
            binary="${optimized_binary}"
            ;;
        *)
            fail "unknown benchmark variant: ${variant}"
            ;;
    esac

    printf '\n[round %s/%s] %s (custom passes %s)\n' \
        "${round}" \
        "${runs}" \
        "${variant}" \
        "$([[ "${variant}" == optimized ]] && echo enabled || echo disabled)"

    started_ns="$(monotonic_now_ns)"
    set +e
    "${binary}" 2>&1 | sed -u "s/^/[${variant}] /"
    pipeline_status=("${PIPESTATUS[@]}")
    set -e
    (( pipeline_status[0] == 0 )) \
        || fail "${variant} executable failed with status ${pipeline_status[0]}"
    (( pipeline_status[1] == 0 )) \
        || fail "could not stream ${variant} output (status ${pipeline_status[1]})"
    finished_ns="$(monotonic_now_ns)"
    (( finished_ns > started_ns )) \
        || fail "${variant} produced a non-positive monotonic elapsed sample"
    elapsed_ns=$((finished_ns - started_ns))
    printf '%s\t%s\t%s\n' "${round}" "${variant}" "${elapsed_ns}" \
        >> "${results_file}"
}

for ((round = 1; round <= runs; round++)); do
    if (( round % 2 == 1 )); then
        run_variant "${round}" baseline
        run_variant "${round}" optimized
    else
        run_variant "${round}" optimized
        run_variant "${round}" baseline
    fi
done

echo
awk -F '\t' -v rounds="${runs}" '
    NR == 1 { next }
    $2 == "baseline" { baseline[$1] = $3 }
    $2 == "optimized" { optimized[$1] = $3 }
    END {
        print "round\tbaseline_s\toptimized_s\toptimized_speedup_percent"
        for (round = 1; round <= rounds; round++) {
            if (!(round in baseline) || !(round in optimized)) {
                print "redb benchmark comparison: incomplete result pair" > "/dev/stderr"
                exit 1
            }
            baseline_total += baseline[round]
            optimized_total += optimized[round]
            printf "%d\t%.3f\t%.3f\t%+.2f%%\n", \
                round, \
                baseline[round] / 1000000000, \
                optimized[round] / 1000000000, \
                (baseline[round] / optimized[round] - 1) * 100
        }
        printf "mean\t%.3f\t%.3f\t%+.2f%%\n", \
            baseline_total / rounds / 1000000000, \
            optimized_total / rounds / 1000000000, \
            (baseline_total / optimized_total - 1) * 100
    }
' "${results_file}"

if [[ "${temporary_results}" == false ]]; then
    printf 'raw results: %s\n' "${results_file}"
fi
