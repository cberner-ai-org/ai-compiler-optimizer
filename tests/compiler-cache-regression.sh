#!/usr/bin/env bash
set -euo pipefail

toolchain_root="${CUSTOM_TOOLCHAIN_ROOT:-/opt/rust-custom}"
probe_manifest="${COMPILER_CACHE_PROBE_MANIFEST:-/opt/compiler-cache-probe/Cargo.toml}"
wrapper="${CUSTOM_TOOLCHAIN_WRAPPER:-/usr/local/bin/with-custom-toolchain}"
probe_root="$(mktemp -d)"
trap 'rm -rf -- "${probe_root}"' EXIT

shopt -s nullglob
driver_paths=("${toolchain_root}"/lib/librustc_driver-*.so)
(( ${#driver_paths[@]} > 0 ))
plugin_path="${toolchain_root}/lib/libaco_keyhole_pass.so"
[[ -s "${plugin_path}" ]]

# The release toolchain is immutable. Exercise artifact mutation against a
# disposable fingerprint fixture while Cargo continues to invoke the shipped
# compiler through RUSTC.
compiler_fixture="${probe_root}/compiler-fixture"
mkdir -p "${compiler_fixture}/bin" "${compiler_fixture}/lib"
cp --archive --reflink=auto \
    "${toolchain_root}/bin/rustc" \
    "${compiler_fixture}/bin/rustc"
cp --archive --reflink=auto \
    "${driver_paths[@]}" \
    "${compiler_fixture}/lib/"
cp --archive --reflink=auto \
    "${plugin_path}" \
    "${compiler_fixture}/lib/libaco_keyhole_pass.so"
cp --archive \
    "${toolchain_root}/.compiler-build-id" \
    "${compiler_fixture}/.compiler-build-id"
# CUSTOM_TOOLCHAIN_ROOT selects the disposable fingerprint inputs below. Keep
# actual compilations on the complete shipped sysroot.
export ACO_TOOLCHAIN_ROOT="${ACO_TOOLCHAIN_ROOT:-${toolchain_root}}"
export CUSTOM_TOOLCHAIN_ROOT="${compiler_fixture}"

rustflags_case=""
cargo_target_dir=""

run_probe() {
    local log_path="$1"
    local -a cargo_environment=(
        env
        -u CARGO_ENCODED_RUSTFLAGS
        -u RUSTFLAGS
        "CARGO_TARGET_DIR=${cargo_target_dir}"
    )

    # Cargo chooses the encoded channel by variable presence, not content.
    # Isolate each state so an invoking environment cannot mask a regression.
    case "${rustflags_case}" in
        unset)
            ;;
        encoded-empty)
            cargo_environment+=(CARGO_ENCODED_RUSTFLAGS=)
            ;;
        encoded-populated)
            cargo_environment+=(CARGO_ENCODED_RUSTFLAGS=-Cdebuginfo=0)
            ;;
        rustflags-populated)
            cargo_environment+=(RUSTFLAGS=-Cdebuginfo=0)
            ;;
        *)
            echo "compiler cache regression: unknown rustflags case: ${rustflags_case}" >&2
            exit 1
            ;;
    esac

    "${cargo_environment[@]}" "${wrapper}" cargo build \
        --locked \
        --manifest-path "${probe_manifest}" \
        --verbose \
        >"${log_path}" 2>&1
}

expect_probe_state() {
    local label="$1"
    local expected="$2"
    local log_path="${probe_root}/${rustflags_case}-${label}.log"

    if ! run_probe "${log_path}"; then
        echo \
            "compiler cache regression: Cargo failed for ${rustflags_case} after ${label}" \
            >&2
        sed -n '1,120p' "${log_path}" >&2
        exit 1
    fi
    if ! grep --fixed-strings --quiet \
        "${expected} compiler-cache-probe" \
        "${log_path}"; then
        echo \
            "compiler cache regression: expected ${expected} for ${rustflags_case} after ${label}" \
            >&2
        sed -n '1,120p' "${log_path}" >&2
        exit 1
    fi
}

exercise_rustflags_case() {
    rustflags_case="$1"
    cargo_target_dir="${probe_root}/target-${rustflags_case}"

    expect_probe_state first Compiling
    expect_probe_state unchanged Fresh

    touch "${compiler_fixture}/bin/rustc"
    expect_probe_state rustc-only-change Compiling
    expect_probe_state rustc-unchanged Fresh
}

exercise_rustflags_case unset
exercise_rustflags_case encoded-empty
exercise_rustflags_case encoded-populated
exercise_rustflags_case rustflags-populated

fixture_driver_paths=("${compiler_fixture}"/lib/librustc_driver-*.so)
touch "${fixture_driver_paths[@]}"
expect_probe_state driver-only-change Compiling
expect_probe_state driver-unchanged Fresh

touch "${compiler_fixture}/lib/libaco_keyhole_pass.so"
expect_probe_state plugin-only-change Compiling
expect_probe_state plugin-unchanged Fresh

echo "compiler cache regression passed"
