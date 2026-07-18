#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "keyhole rustc wrapper: $*" >&2
    exit 1
}

toolchain_root="${ACO_TOOLCHAIN_ROOT:-/opt/rust-custom}"
rustc_path="${toolchain_root}/bin/rustc"
plugin_path="${toolchain_root}/lib/libaco_keyhole_pass.so"

[[ -x "${rustc_path}" ]] || fail "missing compiler executable: ${rustc_path}"
[[ -s "${plugin_path}" ]] || fail "missing LLVM pass plugin: ${plugin_path}"

exec "${rustc_path}" \
    "-Zllvm-plugins=${plugin_path}" \
    "-Cpasses=aco-keyhole" \
    "$@"
