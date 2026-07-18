#!/usr/bin/env bash
set -euo pipefail

toolchain_root="${CUSTOM_TOOLCHAIN_ROOT:-/opt/rust-custom}"
probe_manifest="${COMPILER_CACHE_PROBE_MANIFEST:-/opt/compiler-cache-probe/Cargo.toml}"
variant_wrapper="${COMPILER_VARIANT_WRAPPER:-/usr/local/bin/with-compiler-variant}"
artifact_manifest_writer="${COMPILER_ARTIFACT_WRITER:-/usr/local/bin/write-compiler-artifact-manifest}"
probe_root="$(mktemp -d)"
trap 'rm -rf -- "${probe_root}"' EXIT

shopt -s nullglob
driver_paths=("${toolchain_root}"/lib/librustc_driver-*.so)
(( ${#driver_paths[@]} > 0 ))
plugin_path="${toolchain_root}/lib/libaco_optimizer.so"
optimizer_wrapper="${CUSTOM_RUSTC_WRAPPER:-/usr/local/bin/rustc-with-aco-passes}"
[[ -s "${plugin_path}" ]]
[[ -x "${optimizer_wrapper}" ]]

# The release toolchain is immutable. Exercise artifact mutation against a
# disposable identity fixture while compilations use the complete shipped
# sysroot and optimizer plugin through ACO_TOOLCHAIN_ROOT.
compiler_fixture="${probe_root}/compiler-fixture"
mkdir -p \
    "${compiler_fixture}/bin" \
    "${compiler_fixture}/lib/rustlib/fixture/lib"
cp --archive --reflink=auto \
    "${toolchain_root}/bin/rustc" \
    "${compiler_fixture}/bin/rustc"
cp --archive --reflink=auto \
    "${driver_paths[@]}" \
    "${compiler_fixture}/lib/"
cp --archive --reflink=auto \
    "${plugin_path}" \
    "${compiler_fixture}/lib/libaco_optimizer.so"
cp --archive \
    "${toolchain_root}/.compiler-build-id" \
    "${compiler_fixture}/.compiler-build-id"
cp --archive \
    "${optimizer_wrapper}" \
    "${compiler_fixture}/rustc-with-aco-passes"
printf 'LLVM identity fixture\n' \
    > "${compiler_fixture}/lib/libLLVM-fixture.so"
printf 'sysroot identity fixture\n' \
    > "${compiler_fixture}/lib/rustlib/fixture/lib/libstd-fixture.rlib"

export ACO_TOOLCHAIN_ROOT="${toolchain_root}"
export CUSTOM_TOOLCHAIN_ROOT="${compiler_fixture}"
export CUSTOM_RUSTC_WRAPPER="${compiler_fixture}/rustc-with-aco-passes"
export CARGO_TARGET_DIR="${probe_root}/target"

refresh_compiler_artifact_manifest() {
    "${artifact_manifest_writer}"
}

refresh_compiler_artifact_manifest

run_probe() {
    local variant="$1"
    local log_path="$2"

    "${variant_wrapper}" "${variant}" cargo build \
        --locked \
        --manifest-path "${probe_manifest}" \
        --verbose \
        > "${log_path}" 2>&1
}

expect_probe_state() {
    local variant="$1"
    local label="$2"
    local expected="$3"
    local log_path="${probe_root}/${variant}-${label}.log"

    if ! run_probe "${variant}" "${log_path}"; then
        echo \
            "compiler cache regression: ${variant} Cargo failed after ${label}" \
            >&2
        sed -n '1,120p' "${log_path}" >&2
        exit 1
    fi
    if ! grep --fixed-strings --quiet \
        "${expected} compiler-cache-probe" \
        "${log_path}"; then
        echo \
            "compiler cache regression: expected ${expected} for ${variant} after ${label}" \
            >&2
        sed -n '1,120p' "${log_path}" >&2
        exit 1
    fi
}

expect_both_variants() {
    local label="$1"
    local expected="$2"

    expect_probe_state baseline "${label}" "${expected}"
    expect_probe_state optimized "${label}" "${expected}"
}

expect_both_variants first Compiling
expect_both_variants unchanged Fresh

touch "${compiler_fixture}/bin/rustc"
refresh_compiler_artifact_manifest
expect_both_variants rustc-only-change Compiling
expect_both_variants rustc-unchanged Fresh

fixture_driver_paths=("${compiler_fixture}"/lib/librustc_driver-*.so)
touch "${fixture_driver_paths[@]}"
refresh_compiler_artifact_manifest
expect_both_variants driver-only-change Compiling
expect_both_variants driver-unchanged Fresh

printf 'LLVM mutation\n' >> "${compiler_fixture}/lib/libLLVM-fixture.so"
refresh_compiler_artifact_manifest
expect_both_variants llvm-only-change Compiling
expect_both_variants llvm-unchanged Fresh

printf 'sysroot mutation\n' \
    >> "${compiler_fixture}/lib/rustlib/fixture/lib/libstd-fixture.rlib"
refresh_compiler_artifact_manifest
expect_both_variants sysroot-only-change Compiling
expect_both_variants sysroot-unchanged Fresh

touch "${compiler_fixture}/lib/libaco_optimizer.so"
expect_probe_state baseline plugin-only-change Fresh
expect_probe_state optimized plugin-only-change Compiling
expect_probe_state optimized plugin-unchanged Fresh

touch "${compiler_fixture}/rustc-with-aco-passes"
expect_probe_state baseline wrapper-only-change Fresh
expect_probe_state optimized wrapper-only-change Compiling
expect_probe_state optimized wrapper-unchanged Fresh

echo "compiler cache regression passed"
