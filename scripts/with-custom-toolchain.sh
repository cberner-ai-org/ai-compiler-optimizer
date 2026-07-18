#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "custom toolchain wrapper: $*" >&2
    exit 1
}

(( $# > 0 )) || fail "a command is required"

toolchain_root="${CUSTOM_TOOLCHAIN_ROOT:-/opt/rust-custom}"
build_id_file="${CUSTOM_TOOLCHAIN_BUILD_ID_FILE:-${toolchain_root}/.compiler-build-id}"
rustc_path="${toolchain_root}/bin/rustc"
plugin_path="${toolchain_root}/lib/libaco_keyhole_pass.so"
rustc_wrapper="${CUSTOM_RUSTC_WRAPPER:-/usr/local/bin/rustc-with-keyhole}"

[[ -s "${build_id_file}" ]] || fail "missing compiler build ID: ${build_id_file}"
[[ -x "${rustc_path}" ]] || fail "missing compiler executable: ${rustc_path}"
[[ -s "${plugin_path}" ]] || fail "missing LLVM pass plugin: ${plugin_path}"
[[ -x "${rustc_wrapper}" ]] || fail "missing rustc wrapper: ${rustc_wrapper}"

shopt -s nullglob
driver_paths=("${toolchain_root}"/lib/librustc_driver-*.so)
(( ${#driver_paths[@]} > 0 )) \
    || fail "no rustc driver library found under ${toolchain_root}/lib"

# Cargo normally identifies rustc through `rustc -vV`. The pinned commit-info
# file makes that insufficient for local compiler edits. Include the source ID,
# binary, driver, plugin, and wrapper contents and metadata (so even
# replacement/touch operations are observed), then inject the result into
# Cargo's tracked rustflags.
compiler_artifact_id="$({
    printf 'source:%s\n' "$(<"${build_id_file}")"
    for artifact in \
        "${rustc_path}" \
        "${driver_paths[@]}" \
        "${plugin_path}" \
        "${rustc_wrapper}"; do
        stat --printf 'file:%n:%s:%Y:%y\n' "${artifact}"
        sha256sum "${artifact}"
    done
} | sha256sum | awk '{print $1}')"

metadata_flag="-Cmetadata=custom-toolchain-${compiler_artifact_id}"
if [[ -n "${CARGO_ENCODED_RUSTFLAGS:-}" ]]; then
    export CARGO_ENCODED_RUSTFLAGS+=$'\x1f'"${metadata_flag}"
else
    export RUSTFLAGS="${RUSTFLAGS:+${RUSTFLAGS} }${metadata_flag}"
fi
export ACO_TOOLCHAIN_ROOT="${ACO_TOOLCHAIN_ROOT:-${toolchain_root}}"
export RUSTC="${rustc_wrapper}"

exec "$@"
