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
cargo_path="${CARGO_PATH:-$(command -v cargo)}"
monotonic_clock="${MONOTONIC_CLOCK_PATH:-/usr/local/bin/aco-monotonic-clock}"
comparison_runner="${BENCHMARK_RUNNER:-/usr/local/bin/compare-redb-benchmarks}"

for input in \
    "${compiler_manifest}" \
    "${compiler_artifact_id_file}" \
    "${plugin_path}" \
    "${optimizer_wrapper}" \
    "${variant_wrapper}" \
    "${redb_lockfile}" \
    "${baseline_binary}" \
    "${optimized_binary}" \
    "${cargo_path}" \
    "${monotonic_clock}" \
    "${comparison_runner}"; do
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
cargo_version="$("${cargo_path}" --version)" \
    || fail "could not read the Cargo version"
cargo_sha256="$(hash_file "${cargo_path}")" \
    || fail "could not hash Cargo"
monotonic_clock_sha256="$(hash_file "${monotonic_clock}")" \
    || fail "could not hash the monotonic clock"
comparison_runner_sha256="$(hash_file "${comparison_runner}")" \
    || fail "could not hash the comparison runner"
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
    printf 'manifest_format\taco-benchmark-provenance-v1\n'
    printf 'build_environment_id\t%s\n' "${BUILD_ENVIRONMENT_ID}"
    printf 'rust_image\t%s\n' "${RUST_IMAGE}"
    printf 'debian_snapshot\t%s\n' "${DEBIAN_SNAPSHOT}"
    printf 'rust_version\t%s\n' "${RUST_VERSION}"
    printf 'rust_commit\t%s\n' "${RUST_COMMIT}"
    printf '%s\n' "${compiler_manifest_contents}"
    printf 'optimizer_pipeline\taco-passes\n'
    printf 'optimizer_plugin_sha256\t%s\n' "${optimizer_plugin_sha256}"
    printf 'optimizer_wrapper_sha256\t%s\n' "${optimizer_wrapper_sha256}"
    printf 'compiler_variant_wrapper_sha256\t%s\n' "${variant_wrapper_sha256}"
    printf 'cargo_version\t%s\n' "${cargo_version}"
    printf 'cargo_sha256\t%s\n' "${cargo_sha256}"
    printf 'monotonic_clock\tclock_gettime(CLOCK_MONOTONIC)\n'
    printf 'monotonic_clock_sha256\t%s\n' "${monotonic_clock_sha256}"
    printf 'comparison_runner_sha256\t%s\n' "${comparison_runner_sha256}"
    printf 'redb_version\t%s\n' "${REDB_VERSION}"
    printf 'redb_commit\t%s\n' "${REDB_COMMIT}"
    printf 'redb_lockfile_sha256\t%s\n' "${redb_lockfile_sha256}"
    printf 'baseline_benchmark_sha256\t%s\n' "${baseline_benchmark_sha256}"
    printf 'optimized_benchmark_sha256\t%s\n' "${optimized_benchmark_sha256}"
} > "${temporary_manifest}"

chmod 0644 "${temporary_manifest}"
mv "${temporary_manifest}" "${output}"
trap - EXIT
