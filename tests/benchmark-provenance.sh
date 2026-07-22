#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf -- "${fixture_root}"' EXIT

toolchain_root="${fixture_root}/toolchain"
cargo_toolchain_root="${fixture_root}/rustup/toolchains/1.97.1-fixture"
mkdir -p \
    "${toolchain_root}/bin" \
    "${toolchain_root}/lib/rustlib/test/lib" \
    "${cargo_toolchain_root}/bin" \
    "${fixture_root}/bin"
printf 'compiler build id\n' > "${toolchain_root}/.compiler-build-id"
printf 'rustc\n' > "${toolchain_root}/bin/rustc"
chmod 0755 "${toolchain_root}/bin/rustc"
printf 'driver\n' > "${toolchain_root}/lib/librustc_driver-fixture.so"
printf 'LLVM\n' > "${toolchain_root}/lib/libLLVM-fixture.so"
printf 'sysroot\n' > "${toolchain_root}/lib/rustlib/test/lib/libstd-fixture.rlib"
printf 'plugin\n' > "${toolchain_root}/lib/libaco_optimizer.so"
printf 'optimizer wrapper\n' > "${fixture_root}/bin/rustc-with-aco-passes"
printf 'variant wrapper\n' > "${fixture_root}/bin/with-compiler-variant"
printf 'mode selector\n' > "${fixture_root}/bin/select-redb-benchmark-mode"
printf 'lockfile\n' > "${fixture_root}/Cargo.lock"
printf 'variant\tbuild_elapsed_ms\tbinary_size_bytes\nbaseline\t1\t9\n' \
    > "${fixture_root}/build-metrics.tsv"
printf 'baseline\n' > "${fixture_root}/redb-benchmark-baseline"
printf 'optimized\n' > "${fixture_root}/redb-benchmark-optimized"
cargo_path="${cargo_toolchain_root}/bin/cargo"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'echo "cargo 1.97.1 (fixture)"' \
    > "${cargo_path}"
chmod 0755 "${cargo_path}"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ "${0##*/}" == cargo ]]; then' \
    '    exec "${FIXTURE_SELECTED_CARGO:?}" "$@"' \
    'fi' \
    'if [[ "${1:-}" == which && "${2:-}" == cargo ]]; then' \
    '    printf "%s\\n" "${FIXTURE_SELECTED_CARGO:?}"' \
    '    exit 0' \
    'fi' \
    'exit 2' \
    > "${fixture_root}/bin/rustup"
chmod 0755 "${fixture_root}/bin/rustup"
ln -s rustup "${fixture_root}/bin/cargo"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'echo 100' \
    > "${fixture_root}/bin/aco-monotonic-clock"
chmod 0755 "${fixture_root}/bin/aco-monotonic-clock"
CUSTOM_TOOLCHAIN_ROOT="${toolchain_root}" \
    "${repo_root}/scripts/write-compiler-artifact-manifest.sh"

write_provenance() {
    local manifest_path="$1"

    PATH="${fixture_root}/bin:${PATH}" \
    FIXTURE_SELECTED_CARGO="${cargo_path}" \
    RUST_IMAGE='registry.invalid/rust@sha256:fixture' \
    RUST_VERSION=1.97.1 \
    RUST_COMMIT=rust-fixture \
    REDB_VERSION=4.1.0 \
    REDB_COMMIT=redb-fixture \
    DEBIAN_SNAPSHOT=20260713T000000Z \
    BUILD_ENVIRONMENT_ID=environment-fixture \
    CUSTOM_TOOLCHAIN_ROOT="${toolchain_root}" \
    CUSTOM_RUSTC_WRAPPER="${fixture_root}/bin/rustc-with-aco-passes" \
    COMPILER_VARIANT_WRAPPER="${fixture_root}/bin/with-compiler-variant" \
    BENCHMARK_MODE_SELECTOR="${fixture_root}/bin/select-redb-benchmark-mode" \
    ACO_BUILD_METRICS_FILE="${fixture_root}/build-metrics.tsv" \
    REDB_LOCKFILE="${fixture_root}/Cargo.lock" \
    ACO_BASELINE_BENCHMARK="${fixture_root}/redb-benchmark-baseline" \
    ACO_OPTIMIZED_BENCHMARK="${fixture_root}/redb-benchmark-optimized" \
    CARGO_PATH="${fixture_root}/bin/cargo" \
    MONOTONIC_CLOCK_PATH="${fixture_root}/bin/aco-monotonic-clock" \
    BENCHMARK_RUNNER="${repo_root}/scripts/compare-redb-benchmarks.sh" \
        "${repo_root}/scripts/write-benchmark-provenance.sh" "${manifest_path}"
}

manifest_value() {
    local key="$1"
    local manifest_path="$2"

    awk -F '\t' -v key="${key}" '$1 == key { print $2 }' "${manifest_path}"
}

manifest="${fixture_root}/benchmark-provenance.tsv"
write_provenance "${manifest}"

if ACO_BENCHMARK_CANDIDATE_VARIANT=midpoint \
    ACO_OPTIMIZER_PIPELINE_NAME=aco-passes \
        write_provenance "${fixture_root}/mismatched-mode.tsv" \
        > "${fixture_root}/mismatched-mode.log" 2>&1; then
    echo "benchmark provenance accepted a mismatched mode and pipeline" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'midpoint requires optimizer pipeline aco-midpoint-only; got aco-passes' \
    "${fixture_root}/mismatched-mode.log"

ACO_BENCHMARK_CANDIDATE_VARIANT=midpoint \
ACO_OPTIMIZER_PIPELINE_NAME=aco-midpoint-only \
    write_provenance "${fixture_root}/midpoint-provenance.tsv"
grep --quiet --fixed-strings \
    $'benchmark_candidate_variant\tmidpoint' \
    "${fixture_root}/midpoint-provenance.tsv"

ACO_BENCHMARK_CANDIDATE_VARIANT=three-way-compare \
ACO_OPTIMIZER_PIPELINE_NAME=aco-three-way-compare-only \
    write_provenance "${fixture_root}/three-way-provenance.tsv"
grep --quiet --fixed-strings \
    $'benchmark_candidate_variant\tthree-way-compare' \
    "${fixture_root}/three-way-provenance.tsv"
grep --quiet --fixed-strings \
    $'optimizer_pipeline\taco-three-way-compare-only' \
    "${fixture_root}/three-way-provenance.tsv"
grep --quiet --fixed-strings \
    $'optimizer_pipeline\taco-midpoint-only' \
    "${fixture_root}/midpoint-provenance.tsv"

grep --quiet --fixed-strings $'manifest_format\taco-benchmark-provenance-v2' "${manifest}"
grep --quiet --fixed-strings $'compiler_build_id\tcompiler build id' "${manifest}"
grep --quiet --fixed-strings $'llvm_library_set_sha256\t' "${manifest}"
grep --quiet --fixed-strings $'redb_commit\tredb-fixture' "${manifest}"
grep --quiet --fixed-strings \
    $'redb_lockfile_sha256\t'"$(sha256sum "${fixture_root}/Cargo.lock" | awk '{print $1}')" \
    "${manifest}"
grep --quiet --fixed-strings \
    $'optimizer_plugin_sha256\t'"$(sha256sum "${toolchain_root}/lib/libaco_optimizer.so" | awk '{print $1}')" \
    "${manifest}"
grep --quiet --fixed-strings \
    $'baseline_benchmark_sha256\t'"$(sha256sum "${fixture_root}/redb-benchmark-baseline" | awk '{print $1}')" \
    "${manifest}"
grep --quiet --fixed-strings \
    $'monotonic_clock_sha256\t'"$(sha256sum "${fixture_root}/bin/aco-monotonic-clock" | awk '{print $1}')" \
    "${manifest}"
grep --quiet --fixed-strings \
    $'comparison_runner_sha256\t'"$(sha256sum "${repo_root}/scripts/compare-redb-benchmarks.sh" | awk '{print $1}')" \
    "${manifest}"
grep --quiet --fixed-strings $'benchmark_candidate_variant\toptimized' "${manifest}"
grep --quiet --fixed-strings $'optimizer_pipeline\taco-passes' "${manifest}"
grep --quiet --fixed-strings \
    $'benchmark_mode_selector_sha256\t'"$(sha256sum "${fixture_root}/bin/select-redb-benchmark-mode" | awk '{print $1}')" \
    "${manifest}"
grep --quiet --fixed-strings \
    $'build_metrics_sha256\t'"$(sha256sum "${fixture_root}/build-metrics.tsv" | awk '{print $1}')" \
    "${manifest}"
grep --quiet --fixed-strings \
    $'cargo_sha256\t'"$(sha256sum "${cargo_path}" | awk '{print $1}')" \
    "${manifest}"
grep --quiet --fixed-strings \
    $'cargo_proxy_sha256\t'"$(sha256sum "${fixture_root}/bin/rustup" | awk '{print $1}')" \
    "${manifest}"
[[ "$(manifest_value cargo_sha256 "${manifest}")" \
    != "$(manifest_value cargo_proxy_sha256 "${manifest}")" ]]

initial_cargo_sha256="$(manifest_value cargo_sha256 "${manifest}")"
initial_proxy_sha256="$(manifest_value cargo_proxy_sha256 "${manifest}")"
printf '# Cargo-only replacement\n' >> "${cargo_path}"
replacement_manifest="${fixture_root}/replacement-benchmark-provenance.tsv"
write_provenance "${replacement_manifest}"
[[ "$(manifest_value cargo_sha256 "${replacement_manifest}")" \
    != "${initial_cargo_sha256}" ]]
[[ "$(manifest_value cargo_proxy_sha256 "${replacement_manifest}")" \
    == "${initial_proxy_sha256}" ]]

echo "benchmark provenance regression passed"
