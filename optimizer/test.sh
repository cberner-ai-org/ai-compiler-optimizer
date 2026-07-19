#!/usr/bin/env bash
set -euo pipefail

: "${OPT:?OPT must name the matching LLVM opt}"
: "${PLUGIN:?PLUGIN must name the optimizer plugin}"

source_parent="${BASH_SOURCE[0]%/*}"
source_dir="$(cd -- "${source_parent}" && pwd)"
output="$(mktemp)"
trap 'rm -f -- "${output}"' EXIT

"${OPT}" \
    -S \
    -verify-each \
    -load-pass-plugin="${PLUGIN}" \
    -passes=aco-passes \
    "${source_dir}/tests/optimizer.ll" \
    -o "${output}"

signed_i64="$({
    sed -n '/^define i32 @signed_i64/,/^}/p' "${output}"
})"
signed_i64_undef="$({
    sed -n '/^define i32 @signed_i64_undef/,/^}/p' "${output}"
})"
hoisted_i64="$({
    sed -n '/^define i32 @hoisted_i64/,/^}/p' "${output}"
})"
unsupported_i32="$({
    sed -n '/^define i32 @unsupported_i32/,/^}/p' "${output}"
})"
noncanonical_i64="$({
    sed -n '/^define i32 @noncanonical_i64/,/^}/p' "${output}"
})"

grep --quiet --fixed-strings '%aco.left = freeze i64 %left' \
    <<< "${signed_i64}"
grep --quiet --fixed-strings '%aco.right = freeze i64 %right' \
    <<< "${signed_i64}"
grep --quiet --fixed-strings '%aco.less = icmp slt i64 %aco.left, %aco.right' \
    <<< "${signed_i64}"
grep --quiet --fixed-strings '%aco.equal = icmp eq i64 %aco.left, %aco.right' \
    <<< "${signed_i64}"
grep --quiet --fixed-strings \
    'br i1 %aco.less, label %less, label %aco.scmp.nonless' \
    <<< "${signed_i64}"
grep --quiet --fixed-strings \
    'br i1 %aco.equal, label %equal, label %greater' \
    <<< "${signed_i64}"
if grep --quiet --fixed-strings 'call i8 @llvm.scmp.i8.i64' \
    <<< "${signed_i64}"; then
    echo "optimizer test: transformed switch retained llvm.scmp" >&2
    exit 1
fi
grep --quiet --fixed-strings 'phi i32 [ -1, %entry ]' \
    <<< "${signed_i64}"
grep --quiet --fixed-strings 'phi i32 [ 0, %aco.scmp.nonless ]' \
    <<< "${signed_i64}"
grep --quiet --fixed-strings 'phi i32 [ 1, %aco.scmp.nonless ]' \
    <<< "${signed_i64}"

grep --quiet --fixed-strings '%aco.left = freeze i64 undef' \
    <<< "${signed_i64_undef}"
grep --quiet --fixed-strings '%aco.right = freeze i64 %right' \
    <<< "${signed_i64_undef}"
grep --quiet --fixed-strings \
    '%aco.less = icmp slt i64 %aco.left, %aco.right' \
    <<< "${signed_i64_undef}"
grep --quiet --fixed-strings \
    '%aco.equal = icmp eq i64 %aco.left, %aco.right' \
    <<< "${signed_i64_undef}"
grep --quiet --fixed-strings \
    'br i1 %aco.less, label %less, label %aco.scmp.nonless' \
    <<< "${signed_i64_undef}"
grep --quiet --fixed-strings \
    'br i1 %aco.equal, label %equal, label %greater' \
    <<< "${signed_i64_undef}"

grep --quiet --fixed-strings 'call i8 @llvm.scmp.i8.i64' \
    <<< "${hoisted_i64}"
grep --quiet --fixed-strings 'switch i8 %cmp, label %invalid' \
    <<< "${hoisted_i64}"
if grep --quiet --fixed-strings 'aco.scmp.nonless' <<< "${hoisted_i64}"; then
    echo "optimizer test: transformed a comparison from a dominating block" >&2
    exit 1
fi

grep --quiet --fixed-strings 'call i8 @llvm.scmp.i8.i32' \
    <<< "${unsupported_i32}"
grep --quiet --fixed-strings 'call i8 @llvm.scmp.i8.i64' \
    <<< "${noncanonical_i64}"

echo "optimizer pass regression passed"
