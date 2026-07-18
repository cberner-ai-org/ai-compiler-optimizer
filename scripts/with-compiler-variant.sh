#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "compiler variant wrapper: $*" >&2
    exit 1
}

variant="${1:-}"
case "${variant}" in
    baseline|optimized)
        shift
        ;;
    *)
        fail "first argument must be baseline or optimized"
        ;;
esac
(( $# > 0 )) || fail "a command is required"

toolchain_root="${CUSTOM_TOOLCHAIN_ROOT:-/opt/rust-custom}"
runtime_toolchain_root="${ACO_TOOLCHAIN_ROOT:-${toolchain_root}}"
artifact_manifest="${COMPILER_ARTIFACT_MANIFEST:-${toolchain_root}/.compiler-artifacts.tsv}"
artifact_id_file="${COMPILER_ARTIFACT_ID_FILE:-${toolchain_root}/.compiler-artifact-id}"
runtime_rustc_path="${runtime_toolchain_root}/bin/rustc"
plugin_path="${toolchain_root}/lib/libaco_optimizer.so"
rustc_wrapper="${CUSTOM_RUSTC_WRAPPER:-/usr/local/bin/rustc-with-aco-passes}"

[[ -s "${artifact_manifest}" ]] \
    || fail "missing compiler artifact manifest: ${artifact_manifest}"
[[ -s "${artifact_id_file}" ]] \
    || fail "missing compiler artifact ID: ${artifact_id_file}"
[[ -x "${runtime_rustc_path}" ]] \
    || fail "missing compiler executable: ${runtime_rustc_path}"

compiler_artifact_id="$(<"${artifact_id_file}")"
manifest_artifact_id="$(
    awk -F '\t' '
        $1 == "compiler_artifact_id" { value = $2; matches++ }
        END {
            if (matches != 1)
                exit 1
            print value
        }
    ' "${artifact_manifest}"
)" || fail "compiler artifact manifest has no unique artifact ID"
[[ "${compiler_artifact_id}" == "${manifest_artifact_id}" ]] \
    || fail "compiler artifact ID does not match its manifest"

variant_artifacts=("${BASH_SOURCE[0]}")
rustc_command="${runtime_rustc_path}"
if [[ "${variant}" == optimized ]]; then
    [[ -s "${plugin_path}" ]] || fail "missing LLVM pass plugin: ${plugin_path}"
    [[ -x "${rustc_wrapper}" ]] || fail "missing rustc wrapper: ${rustc_wrapper}"
    variant_artifacts+=("${plugin_path}" "${rustc_wrapper}")
    rustc_command="${rustc_wrapper}"
fi

# The toolchain owns the complete core compiler identity. Add only artifacts
# owned by this variant boundary, then select a target without codegen-visible
# identity flags that could bias the A/B benchmark.
variant_artifact_id="$({
    printf 'compiler-artifact:%s\nvariant:%s\n' "${compiler_artifact_id}" "${variant}"
    for artifact in "${variant_artifacts[@]}"; do
        stat --printf 'file:%n:%s:%Y:%y\n' "${artifact}"
        sha256sum "${artifact}"
    done
} | sha256sum | awk '{print $1}')"

target_root="${ACO_CARGO_TARGET_ROOT:-${CARGO_TARGET_DIR:-target}}"
[[ -n "${target_root}" ]] || fail "Cargo target root must not be empty"

export CARGO_TARGET_DIR="${target_root%/}/aco-${variant}-${variant_artifact_id}"
export ACO_TOOLCHAIN_ROOT="${runtime_toolchain_root}"
export RUSTC="${rustc_command}"

exec "$@"
