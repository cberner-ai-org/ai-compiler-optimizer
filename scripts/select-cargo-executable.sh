#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "Cargo artifact selection: $*" >&2
    exit 1
}

target_name="${1:-}"
[[ -n "${target_name}" ]] || fail "a target name is required"

selected=""
while IFS= read -r message; do
    [[ "${message}" == *'"reason":"compiler-artifact"'* ]] || continue
    [[ "${message}" == *'"kind":["bench"]'* ]] || continue
    [[ "${message}" == *"\"name\":\"${target_name}\""* ]] || continue
    [[ "${message}" == *'"executable":"'* ]] \
        || fail "the ${target_name} artifact has no executable"

    executable="${message#*\"executable\":\"}"
    executable="${executable%%\"*}"
    [[ -n "${executable}" ]] || fail "the ${target_name} executable path is empty"
    [[ -z "${selected}" ]] \
        || fail "Cargo reported more than one ${target_name} bench executable"
    selected="${executable}"
done

[[ -n "${selected}" ]] \
    || fail "Cargo did not report a ${target_name} bench executable"
printf '%s\n' "${selected}"
