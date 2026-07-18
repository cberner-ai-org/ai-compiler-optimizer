#!/usr/bin/env bash
set -euo pipefail

: "${LLVM_CONFIG:?LLVM_CONFIG must name the rustc llvm-config}"
: "${OUTPUT:?OUTPUT must name the pass plugin to create}"

llvm_version="$("${LLVM_CONFIG}" --version)"
[[ "${llvm_version}" == 22.* ]] || {
    echo "keyhole plugin requires rustc's LLVM 22; found ${llvm_version}" >&2
    exit 1
}

# rustc's CI LLVM lives at a path without spaces. Keep each llvm-config flag
# as a separate compiler argument rather than evaluating its output as shell.
llvm_cxxflags_output="$("${LLVM_CONFIG}" --cxxflags)"
read -r -a llvm_cxxflags <<< "${llvm_cxxflags_output}"
source_parent="${BASH_SOURCE[0]%/*}"
source_dir="$(cd -- "${source_parent}" && pwd)"

"${CXX:-c++}" \
    "${llvm_cxxflags[@]}" \
    -fPIC \
    -O3 \
    -shared \
    "${source_dir}/KeyholePass.cpp" \
    -o "${OUTPUT}"
