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

[[ -s "${build_id_file}" ]] || fail "missing compiler build ID: ${build_id_file}"
[[ -x "${rustc_path}" ]] || fail "missing compiler executable: ${rustc_path}"

shopt -s nullglob
driver_paths=("${toolchain_root}"/lib/librustc_driver-*.so)
(( ${#driver_paths[@]} > 0 )) \
    || fail "no rustc driver library found under ${toolchain_root}/lib"

# Cargo normally identifies rustc through `rustc -vV`. The pinned commit-info
# file makes that insufficient for local compiler edits. Include the source ID,
# binary contents, and file metadata (so even replacement/touch operations are
# observed), then inject the result into Cargo's tracked rustflags.
compiler_artifact_id="$({
    printf 'source:%s\n' "$(<"${build_id_file}")"
    for artifact in "${rustc_path}" "${driver_paths[@]}"; do
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

exec "$@"
