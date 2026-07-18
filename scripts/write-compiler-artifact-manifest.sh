#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

fail() {
    echo "compiler artifact manifest: $*" >&2
    exit 1
}

toolchain_root="${CUSTOM_TOOLCHAIN_ROOT:-/opt/rust-custom}"
build_id_file="${CUSTOM_TOOLCHAIN_BUILD_ID_FILE:-${toolchain_root}/.compiler-build-id}"
manifest="${COMPILER_ARTIFACT_MANIFEST:-${toolchain_root}/.compiler-artifacts.tsv}"
artifact_id_file="${COMPILER_ARTIFACT_ID_FILE:-${toolchain_root}/.compiler-artifact-id}"
rustc_path="${toolchain_root}/bin/rustc"
sysroot_root="${toolchain_root}/lib/rustlib"

[[ -s "${build_id_file}" ]] || fail "missing compiler build ID: ${build_id_file}"
[[ -x "${rustc_path}" ]] || fail "missing compiler executable: ${rustc_path}"
[[ -d "${sysroot_root}" ]] || fail "missing compiler sysroot: ${sysroot_root}"

shopt -s nullglob
driver_paths=("${toolchain_root}"/lib/librustc_driver-*.so)
llvm_paths=("${toolchain_root}"/lib/libLLVM*.so*)
(( ${#driver_paths[@]} > 0 )) \
    || fail "no rustc driver library found under ${toolchain_root}/lib"
(( ${#llvm_paths[@]} > 0 )) \
    || fail "no LLVM library found under ${toolchain_root}/lib"

mapfile -d '' -t sysroot_paths < <(
    find "${sysroot_root}" -type f -print0 | sort -z
)
(( ${#sysroot_paths[@]} > 0 )) || fail "compiler sysroot contains no files"

relative_path() {
    local path="$1"
    [[ "${path}" == "${toolchain_root}/"* ]] \
        || fail "artifact is outside the toolchain root: ${path}"
    printf '%s\n' "${path#"${toolchain_root}/"}"
}

hash_file() {
    sha256sum "$1" | awk '{print $1}'
}

hash_file_set() {
    (( $# > 0 )) || fail "cannot hash an empty file set"
    local file_hash
    local path
    {
        for path in "$@"; do
            printf 'file:%s:' "$(relative_path "${path}")"
            file_hash="$(hash_file "${path}")" || return 1
            printf '%s\n' "${file_hash}"
        done
    } | sha256sum | awk '{print $1}'
}

all_artifacts=(
    "${rustc_path}"
    "${driver_paths[@]}"
    "${llvm_paths[@]}"
    "${sysroot_paths[@]}"
)
compiler_artifact_id="$({
    printf 'compiler-build:%s\n' "$(<"${build_id_file}")"
    for path in "${all_artifacts[@]}"; do
        printf 'file:%s:' "$(relative_path "${path}")"
        stat --printf '%s:%Y:%y:%a\n' "${path}" || exit 1
        file_hash="$(hash_file "${path}")" || exit 1
        printf '%s\n' "${file_hash}"
    done
} | sha256sum | awk '{print $1}')" \
    || fail "could not compute the compiler artifact ID"

rustc_sha256="$(hash_file "${rustc_path}")" \
    || fail "could not hash rustc"
driver_set_sha256="$(hash_file_set "${driver_paths[@]}")" \
    || fail "could not hash the rustc driver set"
llvm_set_sha256="$(hash_file_set "${llvm_paths[@]}")" \
    || fail "could not hash the LLVM library set"
sysroot_sha256="$(hash_file_set "${sysroot_paths[@]}")" \
    || fail "could not hash the compiler sysroot"

manifest_directory="${manifest%/*}"
if [[ "${manifest_directory}" == "${manifest}" ]]; then
    manifest_directory=.
fi
id_directory="${artifact_id_file%/*}"
if [[ "${id_directory}" == "${artifact_id_file}" ]]; then
    id_directory=.
fi
mkdir -p "${manifest_directory}" "${id_directory}"
temporary_manifest="$(mktemp "${manifest_directory}/.compiler-artifacts.XXXXXX")"
temporary_id="$(mktemp "${id_directory}/.compiler-artifact-id.XXXXXX")"
trap 'rm -f -- "${temporary_manifest}" "${temporary_id}"' EXIT

{
    printf 'compiler_manifest_format\taco-compiler-artifacts-v1\n'
    printf 'compiler_build_id\t%s\n' "$(<"${build_id_file}")"
    printf 'compiler_artifact_id\t%s\n' "${compiler_artifact_id}"
    printf 'rustc_sha256\t%s\n' "${rustc_sha256}"
    printf 'rustc_driver_set_sha256\t%s\n' "${driver_set_sha256}"
    printf 'llvm_library_set_sha256\t%s\n' "${llvm_set_sha256}"
    printf 'compiler_sysroot_sha256\t%s\n' "${sysroot_sha256}"
} > "${temporary_manifest}"
printf '%s\n' "${compiler_artifact_id}" > "${temporary_id}"

chmod 0644 "${temporary_manifest}" "${temporary_id}"
mv "${temporary_manifest}" "${manifest}"
mv "${temporary_id}" "${artifact_id_file}"
trap - EXIT
