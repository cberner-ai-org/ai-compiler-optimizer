#!/usr/bin/env bash
set -euo pipefail

variant="${1:-}"
destination="${2:-}"
case "${variant}" in
    baseline|optimized|midpoint|slice-comparison|key-comparisons)
        ;;
    *)
        echo "usage: $0 baseline|optimized|midpoint|slice-comparison|key-comparisons DESTINATION" >&2
        exit 2
        ;;
esac
[[ -n "${destination}" ]] || {
    echo "usage: $0 baseline|optimized|midpoint|slice-comparison|key-comparisons DESTINATION" >&2
    exit 2
}

messages_file="$(mktemp)"
trap 'rm -f -- "${messages_file}"' EXIT
metrics_file="${ACO_BUILD_METRICS_FILE:-}"
started_ns=""
if [[ -n "${metrics_file}" ]]; then
    monotonic_clock="${ACO_MONOTONIC_CLOCK:-/usr/local/bin/aco-monotonic-clock}"
    [[ -x "${monotonic_clock}" ]] || {
        echo "build metrics clock is not executable: ${monotonic_clock}" >&2
        exit 1
    }
    started_ns="$("${monotonic_clock}")"
    [[ "${started_ns}" =~ ^[0-9]+$ ]] || {
        echo "build metrics clock returned a non-integer value: ${started_ns}" >&2
        exit 1
    }
fi

# Keep Cargo's human progress and diagnostics streaming on stderr while
# retaining this invocation's JSON event stream as the sole authority for
# executable selection.
set +e
with-compiler-variant "${variant}" cargo bench \
    --locked \
    --no-run \
    --package redb-bench \
    --bench redb_benchmark \
    --message-format=json-render-diagnostics \
    | tee "${messages_file}" > /dev/null
pipeline_status=("${PIPESTATUS[@]}")
set -e

(( pipeline_status[0] == 0 )) \
    || exit "${pipeline_status[0]}"
(( pipeline_status[1] == 0 )) \
    || exit "${pipeline_status[1]}"

benchmark_path="$(
    select-cargo-executable redb_benchmark < "${messages_file}"
)"
[[ -x "${benchmark_path}" ]] \
    || { echo "Cargo-reported benchmark is not executable: ${benchmark_path}" >&2; exit 1; }

install --mode 0755 "${benchmark_path}" "${destination}"
if [[ -n "${metrics_file}" ]]; then
    finished_ns="$("${monotonic_clock}")"
    [[ "${finished_ns}" =~ ^[0-9]+$ ]] || {
        echo "build metrics clock returned a non-integer value: ${finished_ns}" >&2
        exit 1
    }
    (( finished_ns > started_ns )) || {
        echo "build metrics clock produced a non-positive sample" >&2
        exit 1
    }
    metrics_directory="${metrics_file%/*}"
    [[ "${metrics_directory}" != "${metrics_file}" ]] || metrics_directory=.
    mkdir -p "${metrics_directory}"
    if [[ ! -e "${metrics_file}" ]]; then
        printf 'variant\tbuild_elapsed_ms\tbinary_size_bytes\n' > "${metrics_file}"
    fi
    printf '%s\t%s\t%s\n' \
        "${variant}" \
        "$(((finished_ns - started_ns) / 1000000))" \
        "$(stat --printf '%s' "${destination}")" \
        >> "${metrics_file}"
fi
echo "installed ${variant} Cargo-reported benchmark: ${benchmark_path}"
