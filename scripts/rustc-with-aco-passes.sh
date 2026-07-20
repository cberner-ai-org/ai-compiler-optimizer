#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "ACO rustc wrapper: $*" >&2
    exit 1
}

toolchain_root="${ACO_TOOLCHAIN_ROOT:-/opt/rust-custom}"
rustc_path="${toolchain_root}/bin/rustc"
plugin_path="${toolchain_root}/lib/libaco_optimizer.so"
pipeline="${ACO_OPTIMIZER_PIPELINE:-aco-passes}"

[[ -x "${rustc_path}" ]] || fail "missing compiler executable: ${rustc_path}"
[[ -s "${plugin_path}" ]] || fail "missing LLVM pass plugin: ${plugin_path}"
case "${pipeline}" in
    aco-passes|aco-midpoint-only|aco-slice-comparison-only|aco-key-comparisons|aco-all-passes)
        ;;
    *)
        fail "unsupported optimizer pipeline: ${pipeline}"
        ;;
esac

exec "${rustc_path}" \
    "-Zllvm-plugins=${plugin_path}" \
    "-Cpasses=${pipeline}" \
    "$@"
