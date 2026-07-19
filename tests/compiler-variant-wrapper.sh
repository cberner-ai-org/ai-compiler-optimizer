#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf -- "${fixture_root}"' EXIT

mkdir -p \
    "${fixture_root}/bin" \
    "${fixture_root}/lib/rustlib/fixture/lib"
printf 'fixture build id\n' > "${fixture_root}/.compiler-build-id"
printf 'driver fixture\n' > "${fixture_root}/lib/librustc_driver-fixture.so"
printf 'LLVM fixture\n' > "${fixture_root}/lib/libLLVM-fixture.so"
printf 'sysroot fixture\n' \
    > "${fixture_root}/lib/rustlib/fixture/lib/libstd-fixture.rlib"
printf 'plugin fixture\n' > "${fixture_root}/lib/libaco_optimizer.so"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$@"' \
    > "${fixture_root}/bin/rustc"
chmod 0755 "${fixture_root}/bin/rustc"
CUSTOM_TOOLCHAIN_ROOT="${fixture_root}" \
    "${repo_root}/scripts/write-compiler-artifact-manifest.sh"

mapfile -t actual < <(
    ACO_TOOLCHAIN_ROOT="${fixture_root}" \
        "${repo_root}/scripts/rustc-with-aco-passes.sh" --version --verbose
)
expected=(
    "-Zllvm-plugins=${fixture_root}/lib/libaco_optimizer.so"
    "-Cpasses=aco-passes"
    "--version"
    "--verbose"
)

(( ${#actual[@]} == ${#expected[@]} )) || {
    echo "ACO rustc wrapper passed unexpected arguments" >&2
    printf 'expected: %q\n' "${expected[@]}" >&2
    printf 'actual: %q\n' "${actual[@]}" >&2
    exit 1
}
for index in "${!expected[@]}"; do
    [[ "${actual[index]}" == "${expected[index]}" ]] || {
        echo "ACO rustc wrapper argument ${index} did not match" >&2
        printf 'expected: %q\n' "${expected[index]}" >&2
        printf 'actual: %q\n' "${actual[index]}" >&2
        exit 1
    }
done

mapfile -t midpoint_actual < <(
    ACO_TOOLCHAIN_ROOT="${fixture_root}" \
    ACO_OPTIMIZER_PIPELINE=aco-midpoint-only \
        "${repo_root}/scripts/rustc-with-aco-passes.sh" --version
)
[[ "${midpoint_actual[1]}" == "-Cpasses=aco-midpoint-only" ]]

if ACO_TOOLCHAIN_ROOT="${fixture_root}" \
    ACO_OPTIMIZER_PIPELINE=unreviewed-pipeline \
        "${repo_root}/scripts/rustc-with-aco-passes.sh" --version \
        > "${fixture_root}/invalid-pipeline.log" 2>&1; then
    echo "ACO rustc wrapper accepted an unreviewed pipeline" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'unsupported optimizer pipeline: unreviewed-pipeline' \
    "${fixture_root}/invalid-pipeline.log"

read_variant_environment() {
    local variant="$1"

    CUSTOM_TOOLCHAIN_ROOT="${fixture_root}" \
    CUSTOM_RUSTC_WRAPPER="${repo_root}/scripts/rustc-with-aco-passes.sh" \
    ACO_CARGO_TARGET_ROOT="${fixture_root}/target-root" \
        "${repo_root}/scripts/with-compiler-variant.sh" \
        "${variant}" \
        bash -c 'printf "%s\n%s\n%s\n" "${RUSTC}" "${CARGO_TARGET_DIR}" "${ACO_OPTIMIZER_PIPELINE:-disabled}"'
}

mapfile -t baseline_environment < <(read_variant_environment baseline)
mapfile -t optimized_environment < <(read_variant_environment optimized)
mapfile -t midpoint_environment < <(read_variant_environment midpoint)
mapfile -t slice_environment < <(read_variant_environment slice-comparison)
mapfile -t key_environment < <(read_variant_environment key-comparisons)
[[ "${baseline_environment[0]}" == "${fixture_root}/bin/rustc" ]]
[[ "${baseline_environment[1]}" == "${fixture_root}/target-root/aco-baseline-"* ]]
[[ "${baseline_environment[2]}" == disabled ]]
[[ "${optimized_environment[0]}" == "${repo_root}/scripts/rustc-with-aco-passes.sh" ]]
[[ "${optimized_environment[1]}" == "${fixture_root}/target-root/aco-optimized-"* ]]
[[ "${optimized_environment[2]}" == aco-passes ]]
[[ "${midpoint_environment[1]}" == "${fixture_root}/target-root/aco-midpoint-"* ]]
[[ "${midpoint_environment[2]}" == aco-midpoint-only ]]
[[ "${slice_environment[1]}" == "${fixture_root}/target-root/aco-slice-comparison-"* ]]
[[ "${slice_environment[2]}" == aco-slice-comparison-only ]]
[[ "${key_environment[1]}" == "${fixture_root}/target-root/aco-key-comparisons-"* ]]
[[ "${key_environment[2]}" == aco-key-comparisons ]]
[[ "${baseline_environment[1]}" != "${optimized_environment[1]}" ]]

mv \
    "${fixture_root}/lib/libaco_optimizer.so" \
    "${fixture_root}/lib/libaco_optimizer.missing"
read_variant_environment baseline > /dev/null
for plugin_variant in optimized midpoint slice-comparison key-comparisons; do
    if read_variant_environment "${plugin_variant}" \
        > "${fixture_root}/missing-plugin.log" 2>&1; then
        echo "${plugin_variant} compiler variant accepted a missing plugin" >&2
        exit 1
    fi
done
grep --fixed-strings --quiet \
    "missing LLVM pass plugin: ${fixture_root}/lib/libaco_optimizer.so" \
    "${fixture_root}/missing-plugin.log"

echo "compiler variant wrapper regression passed"
