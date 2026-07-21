#!/usr/bin/env bash
set -euo pipefail

: "${OPT:?OPT must name the matching LLVM opt}"
: "${PLUGIN:?PLUGIN must name the optimizer plugin}"
: "${LLVM_CONFIG:?LLVM_CONFIG must name the rustc llvm-config}"

source_parent="${BASH_SOURCE[0]%/*}"
source_dir="$(cd -- "${source_parent}" && pwd)"
temporary_dir="$(mktemp -d)"
trap 'rm -rf -- "${temporary_dir}"' EXIT
output="${temporary_dir}/optimizer-output.ll"

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

read -r -a llvm_cxxflags <<< "$("${LLVM_CONFIG}" --cxxflags)"
read -r -a llvm_ldflags <<< "$("${LLVM_CONFIG}" --ldflags)"
read -r -a llvm_libraries <<< "$("${LLVM_CONFIG}" --libs)"
read -r -a llvm_system_libraries <<< "$("${LLVM_CONFIG}" --system-libs)"

"${CXX:-c++}" \
    "${llvm_cxxflags[@]}" \
    -std=c++20 \
    -O2 \
    "${source_dir}/OptimizerPlugin.cpp" \
    "${source_dir}/OptimizerTestDriver.cpp" \
    "${llvm_ldflags[@]}" \
    "${llvm_libraries[@]}" \
    "${llvm_system_libraries[@]}" \
    -Wl,-rpath,"$("${LLVM_CONFIG}" --libdir)" \
    -o "${temporary_dir}/aco-optimizer-test-driver"

run_keyhole_pipeline() {
    local pipeline="$1"
    local output_file="$2"

    "${temporary_dir}/aco-optimizer-test-driver" \
        "${source_dir}/tests/keyhole-input.ll" \
        "${pipeline}" \
        > "${output_file}"
}

match_count() {
    local pattern="$1"
    local input_file="$2"

    grep --count -- "${pattern}" "${input_file}" || true
}

default_output="${temporary_dir}/keyhole-default.ll"
all_output="${temporary_dir}/keyhole-all.ll"
midpoint_output="${temporary_dir}/keyhole-midpoint.ll"
slice_output="${temporary_dir}/keyhole-slice.ll"
key_output="${temporary_dir}/keyhole-key-comparisons.ll"
unproved_memcmp_output="${temporary_dir}/keyhole-unproved-memcmp.ll"
argument_contract_output="${temporary_dir}/keyhole-argument-contract.ll"
call_memory_contract_output="${temporary_dir}/keyhole-call-memory-contract.ll"
declaration_memory_contract_output="${temporary_dir}/keyhole-declaration-memory-contract.ll"
declaration_readwrite_memory_contract_output="${temporary_dir}/keyhole-declaration-readwrite-memory-contract.ll"
declaration_argument_contract_output="${temporary_dir}/keyhole-declaration-argument-contract.ll"
semantic_metadata_output="${temporary_dir}/keyhole-semantic-metadata.ll"
local_memcmp_output="${temporary_dir}/keyhole-local-memcmp.ll"
ordering_call_contract_output="${temporary_dir}/keyhole-ordering-call-contract.ll"
fake_ordering_output="${temporary_dir}/keyhole-fake-ordering.ll"
interleaved_convergent_output="${temporary_dir}/keyhole-interleaved-convergent.ll"
midpoint_trunc_contract_output="${temporary_dir}/keyhole-midpoint-trunc-contract.ll"
run_keyhole_pipeline aco-passes "${default_output}"
run_keyhole_pipeline aco-all-passes "${all_output}"
run_keyhole_pipeline aco-midpoint-only "${midpoint_output}"
run_keyhole_pipeline aco-slice-comparison-only "${slice_output}"
run_keyhole_pipeline aco-key-comparisons "${key_output}"
"${temporary_dir}/aco-optimizer-test-driver" \
    "${source_dir}/tests/keyhole-unproved-memcmp-input.ll" \
    aco-slice-comparison-only \
    > "${unproved_memcmp_output}"
for contract_fixture in \
    argument-contract \
    call-memory-contract \
    declaration-argument-contract \
    declaration-memory-contract \
    declaration-readwrite-memory-contract \
    semantic-metadata \
    local-memcmp \
    ordering-call-contract; do
    input_name="keyhole-${contract_fixture}-input.ll"
    output_name="${temporary_dir}/keyhole-${contract_fixture}.ll"
    "${OPT}" \
        -S \
        -verify-each \
        -load-pass-plugin="${PLUGIN}" \
        -passes=aco-slice-comparison-only \
        "${source_dir}/tests/${input_name}" \
        -o "${output_name}"
done
"${OPT}" \
    -S \
    -verify-each \
    -load-pass-plugin="${PLUGIN}" \
    -passes=aco-slice-comparison-only \
    "${source_dir}/tests/keyhole-interleaved-convergent-input.ll" \
    -o "${interleaved_convergent_output}"
"${OPT}" \
    -S \
    -verify-each \
    -load-pass-plugin="${PLUGIN}" \
    -passes=aco-midpoint-only \
    "${source_dir}/tests/keyhole-midpoint-trunc-contract-input.ll" \
    -o "${midpoint_trunc_contract_output}"
"${temporary_dir}/aco-optimizer-test-driver" \
    "${source_dir}/tests/keyhole-fake-ordering-input.ll" \
    aco-slice-comparison-only \
    --make-fake-scmp \
    > "${fake_ordering_output}"

[[ "$(match_count 'aco.midpoint.result = add nuw' "${default_output}")" == 0 ]]
[[ "$(match_count '^aco.memcmp.check' "${default_output}")" == 0 ]]
[[ "$(match_count '^aco.slice-cmp.check' "${default_output}")" == 0 ]]
[[ "$(match_count '!aco.expanded' "${default_output}")" == 0 ]]

for transformed_output in "${all_output}" "${key_output}"; do
    [[ "$(match_count 'aco.midpoint.result = add nuw' "${transformed_output}")" == 1 ]]
    [[ "$(match_count '^aco.memcmp.check' "${transformed_output}")" == 2 ]]
    [[ "$(match_count '^aco.slice-cmp.check' "${transformed_output}")" == 3 ]]
    [[ "$(match_count '!aco.expanded' "${transformed_output}")" == 5 ]]
done

memcmp_function="$(sed -n \
    '/^define i32 @memcmp_candidate/,/^}/p' \
    "${all_output}")"
grep --quiet --fixed-strings \
    '%aco.memcmp.left.pointer = freeze ptr %left' \
    <<< "${memcmp_function}"
grep --quiet --fixed-strings \
    '%aco.memcmp.right.pointer = freeze ptr %right' \
    <<< "${memcmp_function}"
grep --quiet --fixed-strings \
    'call i32 @memcmp(ptr %aco.memcmp.left.pointer, ptr %aco.memcmp.right.pointer' \
    <<< "${memcmp_function}"

undef_pointer_function="$(sed -n \
    '/^define i32 @memcmp_undef_pointers/,/^}/p' \
    "${all_output}")"
grep --quiet --fixed-strings \
    '%aco.memcmp.left.pointer = freeze ptr undef' \
    <<< "${undef_pointer_function}"
grep --quiet --fixed-strings \
    '%aco.memcmp.right.pointer = freeze ptr undef' \
    <<< "${undef_pointer_function}"
grep --quiet --fixed-strings \
    'call i32 @memcmp(ptr %aco.memcmp.left.pointer, ptr %aco.memcmp.right.pointer' \
    <<< "${undef_pointer_function}"

slice_function="$(sed -n \
    '/^define i8 @slice_compare_candidate/,/^}/p' \
    "${all_output}")"
grep --quiet --fixed-strings 'aco.slice-cmp.check' <<< "${slice_function}"
grep --quiet --fixed-strings \
    '%aco.slice-cmp.left.pointer = freeze ptr %left' \
    <<< "${slice_function}"
grep --quiet --fixed-strings \
    '%aco.slice-cmp.right.pointer = freeze ptr %right' \
    <<< "${slice_function}"
grep --quiet --fixed-strings \
    'call i32 @memcmp(ptr %aco.slice-cmp.left.pointer, ptr %aco.slice-cmp.right.pointer' \
    <<< "${slice_function}"
if grep --quiet --fixed-strings 'aco.scmp.nonless' <<< "${slice_function}"; then
    echo "optimizer test: all-passes pipeline lowered scmp before the slice matcher" >&2
    exit 1
fi

rust_hot_function="$(sed -n \
    '/^define i8 @slice_compare_rust_hot_contract/,/^}/p' \
    "${full_output}")"
grep --quiet --fixed-strings 'aco.slice-cmp.check' <<< "${rust_hot_function}"
[[ "$(grep --count --fixed-strings '!alias.scope' <<< "${rust_hot_function}")" -ge 3 ]]
grep --quiet --fixed-strings \
    'call noundef range(i8 -1, 2) i8 @llvm.scmp.i8.i64' \
    <<< "${rust_hot_function}"

side_effect_function="$(sed -n \
    '/^define i8 @slice_compare_with_interleaved_side_effect/,/^}/p' \
    "${all_output}")"
grep --quiet --fixed-strings 'aco.slice-cmp.check' <<< "${side_effect_function}"
side_effect_join="$(sed -n \
    '/^aco.slice-cmp.join/,/^}/p' \
    <<< "${side_effect_function}")"
grep --quiet --fixed-strings 'call void @side_effect()' \
    <<< "${side_effect_join}"
[[ "$(match_count 'call void @side_effect()' "${all_output}")" == 1 ]]

for constrained_function_name in memcmp_convergent memcmp_musttail memcmp_notail; do
    constrained_function="$(sed -n \
        "/^define i32 @${constrained_function_name}/,/^}/p" \
        "${all_output}")"
    grep --quiet --fixed-strings 'call i32 @memcmp' \
        <<< "${constrained_function}"
    if grep --quiet --fixed-strings 'aco.memcmp.' \
        <<< "${constrained_function}"; then
        echo "optimizer test: transformed constrained ${constrained_function_name} call" >&2
        exit 1
    fi
done

grep --quiet --fixed-strings \
    'call i32 @memcmp(ptr %left, ptr %right, i32 %length)' \
    "${unproved_memcmp_output}"
if grep --quiet --fixed-strings 'aco.memcmp.' "${unproved_memcmp_output}"; then
    echo 'optimizer test: transformed memcmp outside the proved 64-bit/i64 domain' >&2
    exit 1
fi

for unsupported_function_name in \
    memcmp_unproved_partial_nonnull \
    memcmp_unproved_noundef \
    memcmp_unproved_dereferenceable \
    memcmp_unproved_alignment; do
    unsupported_function="$(sed -n \
        "/^define i32 @${unsupported_function_name}/,/^}/p" \
        "${argument_contract_output}")"
    grep --quiet --fixed-strings '@memcmp(' \
        <<< "${unsupported_function}"
    if grep --quiet --fixed-strings 'aco.memcmp.' \
        <<< "${unsupported_function}"; then
        echo "optimizer test: transformed unproved ${unsupported_function_name} contract" >&2
        exit 1
    fi
done
proved_function="$(sed -n \
    '/^define i32 @memcmp_proved_nonnull/,/^}/p' \
    "${argument_contract_output}")"
grep --quiet --fixed-strings 'aco.memcmp.check' <<< "${proved_function}"
[[ "$(match_count '^aco.memcmp.check' "${argument_contract_output}")" == 1 ]]

for unsupported_function_name in \
    memcmp_call_memory_none \
    memcmp_call_inaccessible_memory \
    memcmp_call_argmem_readwrite \
    memcmp_call_argmem_read_inaccessible_write; do
    unsupported_function="$(sed -n \
        "/^define i32 @${unsupported_function_name}/,/^}/p" \
        "${call_memory_contract_output}")"
    if grep --quiet --fixed-strings 'aco.memcmp.' \
        <<< "${unsupported_function}"; then
        echo "optimizer test: transformed incompatible ${unsupported_function_name} effects" >&2
        exit 1
    fi
done
argmem_read_function="$(sed -n \
    '/^define i32 @memcmp_call_argmem_read(/,/^}/p' \
    "${call_memory_contract_output}")"
grep --quiet --fixed-strings 'aco.memcmp.check' \
    <<< "${argmem_read_function}"
[[ "$(match_count '^aco.memcmp.check' "${call_memory_contract_output}")" == 1 ]]
if grep --quiet --fixed-strings 'aco.memcmp.' \
    "${declaration_memory_contract_output}"; then
    echo 'optimizer test: transformed memcmp with memory(none) declaration' >&2
    exit 1
fi
if grep --quiet --fixed-strings 'aco.memcmp.' \
    "${declaration_readwrite_memory_contract_output}"; then
    echo 'optimizer test: transformed memcmp with read-write declaration effects' >&2
    exit 1
fi
if grep --quiet --fixed-strings 'aco.memcmp.' \
    "${declaration_argument_contract_output}"; then
    echo 'optimizer test: transformed memcmp with declaration argument contract' >&2
    exit 1
fi
if grep --quiet --fixed-strings 'aco.memcmp.' \
    "${semantic_metadata_output}"; then
    echo 'optimizer test: transformed memcmp with semantic result metadata' >&2
    exit 1
fi
if grep --quiet --fixed-strings 'aco.memcmp.' \
    "${local_memcmp_output}"; then
    echo 'optimizer test: transformed module-defined memcmp' >&2
    exit 1
fi
for ordering_contract_output in \
    "${ordering_call_contract_output}" \
    "${fake_ordering_output}"; do
    if grep --quiet --fixed-strings 'aco.slice-cmp.' \
        "${ordering_contract_output}"; then
        echo "optimizer test: specialized an unproved ordering call in ${ordering_contract_output}" >&2
        exit 1
    fi
done
grep --quiet --fixed-strings '@llvm.scmp.i8.i64.fake' \
    "${fake_ordering_output}"

grep --quiet --fixed-strings 'call void @side_effect()' \
    "${interleaved_convergent_output}"
grep --quiet --fixed-strings 'convergent' \
    "${interleaved_convergent_output}"
grep --quiet --fixed-strings 'aco.memcmp.check' \
    "${interleaved_convergent_output}"
if grep --quiet --fixed-strings 'aco.slice-cmp.' \
    "${interleaved_convergent_output}"; then
    echo 'optimizer test: relocated an interleaved convergent call' >&2
    exit 1
fi

grep --quiet --fixed-strings 'trunc nsw i128 %half.wide to i64' \
    "${midpoint_trunc_contract_output}"
grep --quiet --fixed-strings 'trunc nuw nsw i128 %half.wide to i64' \
    "${midpoint_trunc_contract_output}"
if grep --quiet --fixed-strings 'aco.midpoint.' \
    "${midpoint_trunc_contract_output}"; then
    echo 'optimizer test: transformed a signed-wrap trunc midpoint' >&2
    exit 1
fi

[[ "$(match_count 'aco.midpoint.result = add nuw' "${midpoint_output}")" == 1 ]]
[[ "$(match_count '^aco.memcmp.check' "${midpoint_output}")" == 0 ]]
[[ "$(match_count '^aco.slice-cmp.check' "${midpoint_output}")" == 0 ]]
[[ "$(match_count '!aco.expanded' "${midpoint_output}")" == 0 ]]

[[ "$(match_count 'aco.midpoint.result = add nuw' "${slice_output}")" == 0 ]]
[[ "$(match_count '^aco.memcmp.check' "${slice_output}")" == 2 ]]
[[ "$(match_count '^aco.slice-cmp.check' "${slice_output}")" == 3 ]]
[[ "$(match_count '!aco.expanded' "${slice_output}")" == 5 ]]

for transformed_output in "${all_output}" "${midpoint_output}" "${key_output}"; do
    grep --quiet '^define i64 @unguarded_binary_search' "${transformed_output}"
    grep --quiet 'trunc nuw i128 %half.wide to i64' "${transformed_output}"
done

# Exercise the plugin's public pipeline parser independently of the linked
# structural driver.
"${OPT}" \
    -S \
    -verify-each \
    -load-pass-plugin="${PLUGIN}" \
    -passes=aco-midpoint-only \
    "${source_dir}/tests/keyhole-input.ll" \
    -o "${temporary_dir}/keyhole-midpoint-opt.ll"
[[ "$(match_count 'aco.midpoint.result = add nuw' "${temporary_dir}/keyhole-midpoint-opt.ll")" == 1 ]]
[[ "$(match_count '^aco.slice-cmp.check' "${temporary_dir}/keyhole-midpoint-opt.ll")" == 0 ]]

# Exercise constrained ordering calls through the public plugin with LLVM's
# verifier after every pass. The generic memcmp expansion remains eligible,
# but slice specialization must not relocate either ordering call.
"${OPT}" \
    -S \
    -verify-each \
    -load-pass-plugin="${PLUGIN}" \
    -passes=aco-slice-comparison-only \
    "${source_dir}/tests/keyhole-constrained-ordering-input.ll" \
    -o "${temporary_dir}/keyhole-constrained-ordering-opt.ll"

for constrained_ordering in musttail convergent notail; do
    constrained_function="$(sed -n \
        "/^define i8 @slice_compare_ordering_${constrained_ordering}/,/^}/p" \
        "${temporary_dir}/keyhole-constrained-ordering-opt.ll")"
    if [[ "${constrained_ordering}" == musttail ]]; then
        grep --quiet --fixed-strings \
            'musttail call i8 @llvm.scmp.i8.i64' \
            <<< "${constrained_function}"
    elif [[ "${constrained_ordering}" == convergent ]]; then
        grep --quiet --fixed-strings \
            'call i8 @llvm.scmp.i8.i64' \
            <<< "${constrained_function}"
        grep --quiet --fixed-strings 'convergent' \
            <<< "${constrained_function}"
    else
        grep --quiet --fixed-strings \
            'notail call i8 @llvm.scmp.i8.i64' \
            <<< "${constrained_function}"
    fi
    if grep --quiet --fixed-strings 'aco.slice-cmp.' \
        <<< "${constrained_function}"; then
        echo "optimizer test: specialized constrained ${constrained_ordering} ordering call" >&2
        exit 1
    fi
done

tail_hint_function="$(sed -n \
    '/^define i8 @slice_compare_ordering_tail_hint/,/^}/p' \
    "${temporary_dir}/keyhole-constrained-ordering-opt.ll")"
grep --quiet --fixed-strings 'aco.slice-cmp.check' \
    <<< "${tail_hint_function}"
grep --quiet --fixed-strings 'call i8 @llvm.scmp.i8.i64' \
    <<< "${tail_hint_function}"
if grep --quiet --fixed-strings 'tail call i8 @llvm.scmp.i8.i64' \
    <<< "${tail_hint_function}"; then
    echo 'optimizer test: retained a stale ordering tail hint after relocation' >&2
    exit 1
fi

echo "optimizer pass regressions passed"
