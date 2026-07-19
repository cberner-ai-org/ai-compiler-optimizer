#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:?usage: build-alive2-with-llvm-config SOURCE BUILD INSTALL LLVM_CONFIG}"
build_dir="${2:?usage: build-alive2-with-llvm-config SOURCE BUILD INSTALL LLVM_CONFIG}"
install_dir="${3:?usage: build-alive2-with-llvm-config SOURCE BUILD INSTALL LLVM_CONFIG}"
llvm_config="${4:?usage: build-alive2-with-llvm-config SOURCE BUILD INSTALL LLVM_CONFIG}"

[[ -x "${llvm_config}" ]] || {
    echo "LLVM config is not executable: ${llvm_config}" >&2
    exit 1
}
[[ "$("${llvm_config}" --version)" == 22.* ]] || {
    echo "Alive2 translation validator requires LLVM 22" >&2
    exit 1
}

cmake \
    -S "${source_dir}" \
    -B "${build_dir}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${install_dir}" \
    -DGIT_EXECUTABLE=/usr/local/bin/alive2-git-version
cmake --build "${build_dir}" --target alive alive-jobserver
cmake --install "${build_dir}"

read -r -a llvm_cxxflags <<< "$("${llvm_config}" --cxxflags)"
read -r -a llvm_ldflags <<< "$("${llvm_config}" --ldflags)"
read -r -a llvm_libs <<< "$("${llvm_config}" --link-shared --libs)"
read -r -a llvm_system_libs <<< "$("${llvm_config}" --system-libs)"

compile_flags=(
    "${llvm_cxxflags[@]}"
    -std=c++20
    -fexceptions
    -frtti
    -fPIC
    -O3
    -Wall
    -Werror
    -Wno-error=restrict
    -DNO_REDIS_SUPPORT
    -I"${source_dir}"
    -I"${build_dir}"
)

objects=()
for source in \
    llvm_util/compare.cpp \
    llvm_util/known_fns.cpp \
    llvm_util/llvm_optimizer.cpp \
    llvm_util/llvm2alive.cpp \
    llvm_util/utils.cpp \
    tools/alive-tv.cpp; do
    object="${build_dir}/${source//\//_}.o"
    source_flags=("${compile_flags[@]}")
    if [[ "${source}" == tools/alive-tv.cpp ]]; then
        # rustc's CI LLVM intentionally omits C++ RTTI. The validator's own
        # translator needs RTTI for Alive2 IR classes, while its command-line
        # entry point instantiates LLVM option classes and must match LLVM.
        source_flags+=(-fno-rtti)
    fi
    "${CXX:-c++}" "${source_flags[@]}" \
        -c "${source_dir}/${source}" \
        -o "${object}"
    objects+=("${object}")
done

"${CXX:-c++}" \
    "${objects[@]}" \
    "${build_dir}/libir.a" \
    "${build_dir}/libsmt.a" \
    "${build_dir}/libtools.a" \
    "${build_dir}/libutil.a" \
    "${llvm_ldflags[@]}" \
    "${llvm_libs[@]}" \
    "${llvm_system_libs[@]}" \
    -lz3 \
    -lz \
    -pthread \
    -Wl,-rpath,/opt/llvm/lib \
    -o "${install_dir}/bin/alive-tv"
