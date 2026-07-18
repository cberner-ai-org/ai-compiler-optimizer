#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf -- "${fixture_root}"' EXIT

mkdir -p "${fixture_root}/bin" "${fixture_root}/lib"
printf 'plugin fixture\n' > "${fixture_root}/lib/libaco_keyhole_pass.so"
chmod 0644 "${fixture_root}/lib/libaco_keyhole_pass.so"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$@"' \
    > "${fixture_root}/bin/rustc"
chmod 0755 "${fixture_root}/bin/rustc"

mapfile -t actual < <(
    ACO_TOOLCHAIN_ROOT="${fixture_root}" \
        "${repo_root}/scripts/rustc-with-keyhole.sh" --version --verbose
)
expected=(
    "-Zllvm-plugins=${fixture_root}/lib/libaco_keyhole_pass.so"
    "-Cpasses=aco-keyhole"
    "--version"
    "--verbose"
)

(( ${#actual[@]} == ${#expected[@]} )) || {
    echo "keyhole rustc wrapper passed unexpected arguments" >&2
    printf 'expected: %q\n' "${expected[@]}" >&2
    printf 'actual: %q\n' "${actual[@]}" >&2
    exit 1
}
for index in "${!expected[@]}"; do
    [[ "${actual[index]}" == "${expected[index]}" ]] || {
        echo "keyhole rustc wrapper argument ${index} did not match" >&2
        printf 'expected: %q\n' "${expected[index]}" >&2
        printf 'actual: %q\n' "${actual[index]}" >&2
        exit 1
    }
done

mv \
    "${fixture_root}/lib/libaco_keyhole_pass.so" \
    "${fixture_root}/lib/libaco_keyhole_pass.missing"
if ACO_TOOLCHAIN_ROOT="${fixture_root}" \
    "${repo_root}/scripts/rustc-with-keyhole.sh" --version \
    > "${fixture_root}/missing-plugin.log" 2>&1; then
    echo "keyhole rustc wrapper accepted a missing plugin" >&2
    exit 1
fi
grep --fixed-strings --quiet \
    "missing LLVM pass plugin: ${fixture_root}/lib/libaco_keyhole_pass.so" \
    "${fixture_root}/missing-plugin.log"

echo "keyhole rustc wrapper regression passed"
