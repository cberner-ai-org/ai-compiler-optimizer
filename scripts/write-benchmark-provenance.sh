#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "benchmark provenance: $*" >&2
    exit 1
}

(( $# == 1 )) || fail "usage: $0 OUTPUT"
output="$1"

: "${RUST_IMAGE:?RUST_IMAGE is required}"
: "${RUST_VERSION:?RUST_VERSION is required}"
: "${RUST_COMMIT:?RUST_COMMIT is required}"
: "${REDB_VERSION:?REDB_VERSION is required}"
: "${REDB_COMMIT:?REDB_COMMIT is required}"
: "${DEBIAN_SNAPSHOT:?DEBIAN_SNAPSHOT is required}"
: "${BUILD_ENVIRONMENT_ID:?BUILD_ENVIRONMENT_ID is required}"

toolchain_root="${CUSTOM_TOOLCHAIN_ROOT:-/opt/rust-custom}"
compiler_manifest="${COMPILER_ARTIFACT_MANIFEST:-${toolchain_root}/.compiler-artifacts.tsv}"
compiler_artifact_id_file="${COMPILER_ARTIFACT_ID_FILE:-${toolchain_root}/.compiler-artifact-id}"
plugin_path="${toolchain_root}/lib/libaco_optimizer.so"
optimizer_wrapper="${CUSTOM_RUSTC_WRAPPER:-/usr/local/bin/rustc-with-aco-passes}"
variant_wrapper="${COMPILER_VARIANT_WRAPPER:-/usr/local/bin/with-compiler-variant}"
redb_lockfile="${REDB_LOCKFILE:-/usr/src/redb/Cargo.lock}"
baseline_binary="${ACO_BASELINE_BENCHMARK:-/usr/local/bin/redb-benchmark-baseline}"
optimized_binary="${ACO_OPTIMIZED_BENCHMARK:-/usr/local/bin/redb-benchmark-optimized}"
candidate_variant="${ACO_BENCHMARK_CANDIDATE_VARIANT:-optimized}"
optimizer_pipeline="${ACO_OPTIMIZER_PIPELINE_NAME:-aco-passes}"
cargo_proxy_path="${CARGO_PATH:-$(command -v cargo)}"
monotonic_clock="${MONOTONIC_CLOCK_PATH:-/usr/local/bin/aco-monotonic-clock}"
comparison_runner="${BENCHMARK_RUNNER:-/usr/local/bin/compare-redb-benchmarks}"
mode_selector="${BENCHMARK_MODE_SELECTOR:-/usr/local/bin/select-redb-benchmark-mode}"
build_metrics="${ACO_BUILD_METRICS_FILE:-/usr/local/share/ai-compiler-optimizer/redb-build-metrics.tsv}"

case "${candidate_variant}" in
    optimized)
        expected_optimizer_pipeline=aco-passes
        ;;
    midpoint)
        expected_optimizer_pipeline=aco-midpoint-only
        ;;
    slice-comparison)
        expected_optimizer_pipeline=aco-slice-comparison-only
        ;;
    key-comparisons)
        expected_optimizer_pipeline=aco-key-comparisons
        ;;
    *)
        fail "unsupported benchmark candidate variant: ${candidate_variant}"
        ;;
esac
[[ "${optimizer_pipeline}" == "${expected_optimizer_pipeline}" ]] ||
    fail "${candidate_variant} requires optimizer pipeline ${expected_optimizer_pipeline}; got ${optimizer_pipeline}"

canonical_path() {
    readlink --canonicalize-existing -- "$1"
}

cargo_proxy_real_path="$(canonical_path "${cargo_proxy_path}")" \
    || fail "could not resolve the Cargo invocation path"
cargo_path="${CARGO_SELECTED_PATH:-}"
if [[ -z "${cargo_path}" ]]; then
    rustup_path="${RUSTUP_PATH:-$(command -v rustup || true)}"
    if [[ -n "${rustup_path}" ]]; then
        rustup_real_path="$(canonical_path "${rustup_path}")" \
            || fail "could not resolve rustup"
    else
        rustup_real_path=""
    fi

    if [[ "${cargo_proxy_real_path}" == "${rustup_real_path}" ]]; then
        cargo_path="$("${rustup_path}" which cargo)" \
            || fail "could not resolve the Cargo executable selected by rustup"
    else
        cargo_path="${cargo_proxy_path}"
    fi
fi
cargo_path="$(canonical_path "${cargo_path}")" \
    || fail "could not resolve the selected Cargo executable"

for input in \
    "${compiler_manifest}" \
    "${compiler_artifact_id_file}" \
    "${plugin_path}" \
    "${optimizer_wrapper}" \
    "${variant_wrapper}" \
    "${redb_lockfile}" \
    "${baseline_binary}" \
    "${optimized_binary}" \
    "${cargo_proxy_path}" \
    "${cargo_path}" \
    "${monotonic_clock}" \
    "${comparison_runner}" \
    "${mode_selector}" \
    "${build_metrics}"; do
    [[ -s "${input}" ]] || fail "missing provenance input: ${input}"
done

hash_file() {
    sha256sum "$1" | awk '{print $1}'
}

manifest_value() {
    local key="$1"
    local source_manifest="$2"
    awk -F '\t' -v key="${key}" '
        $1 == key { value = $2; matches++ }
        END {
            if (matches != 1)
                exit 1
            print value
        }
    ' "${source_manifest}"
}

compiler_artifact_id="$(<"${compiler_artifact_id_file}")"
manifest_artifact_id="$(manifest_value compiler_artifact_id "${compiler_manifest}")" \
    || fail "compiler artifact manifest has no unique artifact ID"
[[ "${compiler_artifact_id}" == "${manifest_artifact_id}" ]] \
    || fail "compiler artifact ID does not match its manifest"
for required_key in \
    compiler_manifest_format \
    compiler_build_id \
    rustc_sha256 \
    rustc_driver_set_sha256 \
    llvm_library_set_sha256 \
    compiler_sysroot_sha256; do
    manifest_value "${required_key}" "${compiler_manifest}" > /dev/null \
        || fail "compiler artifact manifest has no unique ${required_key}"
done

compiler_manifest_contents="$(<"${compiler_manifest}")"
optimizer_plugin_sha256="$(hash_file "${plugin_path}")" \
    || fail "could not hash the optimizer plugin"
optimizer_wrapper_sha256="$(hash_file "${optimizer_wrapper}")" \
    || fail "could not hash the optimizer wrapper"
variant_wrapper_sha256="$(hash_file "${variant_wrapper}")" \
    || fail "could not hash the compiler variant wrapper"
cargo_version="$("${cargo_proxy_path}" --version)" \
    || fail "could not read the Cargo version"
selected_cargo_version="$("${cargo_path}" --version)" \
    || fail "could not read the selected Cargo version"
[[ "${cargo_version}" == "${selected_cargo_version}" ]] \
    || fail "Cargo proxy and selected executable report different versions"
cargo_sha256="$(hash_file "${cargo_path}")" \
    || fail "could not hash the selected Cargo executable"
cargo_proxy_sha256="$(hash_file "${cargo_proxy_path}")" \
    || fail "could not hash the Cargo proxy"
monotonic_clock_sha256="$(hash_file "${monotonic_clock}")" \
    || fail "could not hash the monotonic clock"
comparison_runner_sha256="$(hash_file "${comparison_runner}")" \
    || fail "could not hash the comparison runner"
mode_selector_sha256="$(hash_file "${mode_selector}")" \
    || fail "could not hash the benchmark mode selector"
build_metrics_sha256="$(hash_file "${build_metrics}")" \
    || fail "could not hash the build metrics"
redb_lockfile_sha256="$(hash_file "${redb_lockfile}")" \
    || fail "could not hash the redb lockfile"
baseline_benchmark_sha256="$(hash_file "${baseline_binary}")" \
    || fail "could not hash the baseline benchmark"
optimized_benchmark_sha256="$(hash_file "${optimized_binary}")" \
    || fail "could not hash the optimized benchmark"

manifest_directory="${output%/*}"
if [[ "${manifest_directory}" == "${output}" ]]; then
    manifest_directory=.
fi
mkdir -p "${manifest_directory}"
temporary_manifest="$(mktemp "${manifest_directory}/.benchmark-provenance.XXXXXX")"
trap 'rm -f -- "${temporary_manifest}"' EXIT

{
    printf 'manifest_format\taco-benchmark-provenance-v2\n'
    printf 'build_environment_id\t%s\n' "${BUILD_ENVIRONMENT_ID}"
    printf 'rust_image\t%s\n' "${RUST_IMAGE}"
    printf 'debian_snapshot\t%s\n' "${DEBIAN_SNAPSHOT}"
    printf 'rust_version\t%s\n' "${RUST_VERSION}"
    printf 'rust_commit\t%s\n' "${RUST_COMMIT}"
    printf '%s\n' "${compiler_manifest_contents}"
    printf 'benchmark_candidate_variant\t%s\n' "${candidate_variant}"
    printf 'optimizer_pipeline\t%s\n' "${optimizer_pipeline}"
    printf 'optimizer_plugin_sha256\t%s\n' "${optimizer_plugin_sha256}"
    printf 'optimizer_wrapper_sha256\t%s\n' "${optimizer_wrapper_sha256}"
    printf 'compiler_variant_wrapper_sha256\t%s\n' "${variant_wrapper_sha256}"
    printf 'cargo_version\t%s\n' "${cargo_version}"
    printf 'cargo_sha256\t%s\n' "${cargo_sha256}"
    printf 'cargo_proxy_sha256\t%s\n' "${cargo_proxy_sha256}"
    printf 'monotonic_clock\tclock_gettime(CLOCK_MONOTONIC)\n'
    printf 'monotonic_clock_sha256\t%s\n' "${monotonic_clock_sha256}"
    printf 'comparison_runner_sha256\t%s\n' "${comparison_runner_sha256}"
    printf 'benchmark_mode_selector_sha256\t%s\n' "${mode_selector_sha256}"
    printf 'build_metrics_sha256\t%s\n' "${build_metrics_sha256}"
    printf 'redb_version\t%s\n' "${REDB_VERSION}"
    printf 'redb_commit\t%s\n' "${REDB_COMMIT}"
    printf 'redb_lockfile_sha256\t%s\n' "${redb_lockfile_sha256}"
    printf 'baseline_benchmark_sha256\t%s\n' "${baseline_benchmark_sha256}"
    printf 'baseline_benchmark_size_bytes\t%s\n' "$(stat --printf '%s' "${baseline_binary}")"
    printf 'optimized_benchmark_sha256\t%s\n' "${optimized_benchmark_sha256}"
    printf 'optimized_benchmark_size_bytes\t%s\n' "$(stat --printf '%s' "${optimized_binary}")"
} > "${temporary_manifest}"

chmod 0644 "${temporary_manifest}"
mv "${temporary_manifest}" "${output}"
trap - EXIT
