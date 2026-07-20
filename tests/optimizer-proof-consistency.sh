#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
implementation="${repo_root}/optimizer/OptimizerPlugin.cpp"
proof="${repo_root}/optimizer/proofs/scmp-i64-switch-classification.opt"
undef_proof="${repo_root}/optimizer/proofs/scmp-i64-switch-undef-correlation.opt"
unfrozen_regression="${repo_root}/tests/alive2/00-scmp-i64-switch-unfrozen.opt"
memcmp_proof="${repo_root}/optimizer/proofs/memcmp-first-byte.srctgt.ll"
memcmp_contract_proof="${repo_root}/optimizer/proofs/memcmp-first-byte-call-attrs.srctgt.ll"
pointer_freeze_proof="${repo_root}/optimizer/proofs/single-use-pointer-freeze.srctgt.ll"
slice_equal_proof="${repo_root}/optimizer/proofs/slice-order-equal-after-memcmp-expansion.srctgt.ll"
slice_unequal_proof="${repo_root}/optimizer/proofs/slice-order-unequal-after-memcmp-expansion.srctgt.ll"
slice_zero_proof="${repo_root}/optimizer/proofs/slice-order-zero-after-memcmp-expansion.srctgt.ll"
midpoint_proof="${repo_root}/optimizer/proofs/narrow-ordered-midpoint.srctgt.ll"

for implementation_fragment in \
    'Intrinsic::scmp' \
    'Compare->getParent() != Switch.getParent()' \
    'isIntegerTy(8)' \
    'isIntegerTy(64)' \
    'Value.isAllOnes()' \
    'Value.isZero()' \
    'Value.isOne()' \
    'CreateFreeze(Left, "aco.left")' \
    'CreateFreeze(Right, "aco.right")' \
    'CreateICmpSLT(FrozenLeft, FrozenRight, "aco.less")' \
    'CreateICmpEQ(' \
    'FrozenLeft, FrozenRight, "aco.equal")' \
    'SourceBuilder.CreateCondBr(IsLess, Less, NonLess);' \
    'NonLessBuilder.CreateCondBr(IsEqual, Equal, Greater);'; do
    rg --quiet --fixed-strings "${implementation_fragment}" "${implementation}" || {
        echo "optimizer proof consistency: implementation is missing ${implementation_fragment}" >&2
        exit 1
    }
done

# Keep the C++ eligibility predicate no broader than the ABI and call semantics
# modeled by the tracked memcmp obligation. Adding a supported domain requires
# changing this contract and adding a matching proof in the same diff.
for implementation_fragment in \
    'isProvenMemcmpCall' \
    'hasUnsupportedCallControlContract(Call)' \
    'hasUnsupportedCallControlContract(*Ordering)' \
    'hasUnsupportedCallMetadataContract(Call)' \
    'hasUnsupportedCallMetadataContract(*Ordering)' \
    'hasUnsupportedMemcmpAttributeContract(Call, *Callee)' \
    'hasUnsupportedOrderingAttributeContract(*Ordering,' \
    'OrderingFunction->getIntrinsicID() != llvm::Intrinsic::scmp' \
    'OrderingFunction->getName() != "llvm.scmp.i8.i64"' \
    'llvm::Intrinsic::getAttributes(' \
    '!Callee->isDeclaration()' \
    '!Callee->hasExternalLinkage()' \
    'Call.getAttributes().getParamAttrs(0)' \
    'Call.getAttributes().getParamAttrs(1)' \
    'Call.getAttributes().getParamAttrs(2)' \
    'HasNoCallParameterAttributes' \
    'HasProvenNonnullAttributes' \
    'Callee.getAttributes().getParamAttrs(Index)' \
    'llvm::Attribute::NonNull' \
    'llvm::Attribute::Captures' \
    'Attributes.hasFnAttr(llvm::Attribute::Memory)' \
    'Attributes.getMemoryEffects()' \
    'Effects.onlyReadsMemory()' \
    'Effects.onlyAccessesArgPointees()' \
    'llvm::MemoryEffects::Location::ArgMem' \
    'llvm::isRefSet' \
    'Call.isConvergent()' \
    'Call.isMustTailCall()' \
    'Call.getTailCallKind() == llvm::CallInst::TCK_NoTail' \
    'Call.getCallingConv() != llvm::CallingConv::C' \
    'Call.hasOperandBundles()' \
    'Call.hasFnAttr(llvm::Attribute::NoReturn)' \
    'Call.hasFnAttr(llvm::Attribute::ReturnsTwice)' \
    'Call.hasFnAttr(llvm::Attribute::NoDuplicate)' \
    'hasUnsupportedCallControlContract(*InterleavedCall)' \
    'Memcmp.getArgOperand(0), "aco.slice-cmp.left.pointer")' \
    'Memcmp.getArgOperand(1), "aco.slice-cmp.right.pointer")' \
    'Call.getArgOperand(0), "aco.memcmp.left.pointer")' \
    'Call.getArgOperand(1), "aco.memcmp.right.pointer")' \
    'Memcmp.setArgOperand(0, FrozenLeftPointer)' \
    'Memcmp.setArgOperand(1, FrozenRightPointer)' \
    'Call.setArgOperand(0, FrozenLeftPointer)' \
    'Call.setArgOperand(1, FrozenRightPointer)' \
    '!Layout.isLittleEndian()' \
    'Layout.getPointerSizeInBits(0) != 64' \
    'isIntegerTy(64)' \
    'LeftPointer->getAddressSpace() == 0' \
    'RightPointer->getAddressSpace() == 0'; do
    rg --quiet --fixed-strings "${implementation_fragment}" "${implementation}" || {
        echo "optimizer proof consistency: memcmp matcher is missing ${implementation_fragment}" >&2
        exit 1
    }
done

for implementation_fragment in \
    'Trunc.hasNoUnsignedWrap()' \
    'Trunc.hasNoSignedWrap()' \
    'Trunc.getSrcTy()->isIntegerTy(128)' \
    'Trunc.getDestTy()->isIntegerTy(64)'; do
    rg --quiet --fixed-strings "${implementation_fragment}" "${implementation}" || {
        echo "optimizer proof consistency: midpoint matcher is missing ${implementation_fragment}" >&2
        exit 1
    }
done

for proof_fragment in \
    'target datalayout = "e-p:64:64:64"' \
    '%result = trunc nuw i128 %half_wide to i64' \
    '%delta = sub nuw i64 %maximum, %minimum' \
    '%result = add nuw i64 %minimum, %half_delta'; do
    rg --quiet --fixed-strings "${proof_fragment}" "${midpoint_proof}" || {
        echo "optimizer proof consistency: midpoint proof is missing ${proof_fragment}" >&2
        exit 1
    }
done

for proof_fragment in \
    'define i32 @src(ptr noundef captures(none) %left' \
    '%result = call i32 @memcmp(ptr nonnull %left, ptr nonnull %right, i64 %length)' \
    'define i32 @tgt(ptr noundef captures(none) %left' \
    '%left_pointer = freeze ptr %left' \
    '%right_pointer = freeze ptr %right' \
    '%slow_result = call i32 @memcmp(ptr nonnull %left_pointer, ptr nonnull %right_pointer, i64 %length_frozen)' \
    'declare i32 @memcmp(ptr captures(none), ptr captures(none), i64) memory(argmem: read)'; do
    rg --quiet --fixed-strings "${proof_fragment}" "${memcmp_contract_proof}" || {
        echo "optimizer proof consistency: memcmp contract proof is missing ${proof_fragment}" >&2
        exit 1
    }
done

for proof_fragment in \
    'target datalayout = "e-p:64:64:64"' \
    'define i32 @src(ptr noundef captures(none) %left, ptr noundef captures(none) %right, i64 %length)' \
    '%result = call i32 @memcmp(ptr %left, ptr %right, i64 %length)' \
    'define i32 @tgt(ptr noundef captures(none) %left, ptr noundef captures(none) %right, i64 %length)' \
    '%left_pointer = freeze ptr %left' \
    '%right_pointer = freeze ptr %right' \
    '%slow_result = call i32 @memcmp(ptr %left_pointer, ptr %right_pointer, i64 %length_frozen)' \
    'declare i32 @memcmp(ptr captures(none), ptr captures(none), i64)'; do
    rg --quiet --fixed-strings "${proof_fragment}" "${memcmp_proof}" || {
        echo "optimizer proof consistency: memcmp proof is missing ${proof_fragment}" >&2
        exit 1
    }
done

for proof_fragment in \
    'define ptr @src(ptr %pointer)' \
    'ret ptr %pointer' \
    '%frozen = freeze ptr %pointer' \
    'ret ptr %frozen'; do
    rg --quiet --fixed-strings "${proof_fragment}" "${pointer_freeze_proof}" || {
        echo \
            "optimizer proof consistency: single-use pointer-freeze proof is missing ${proof_fragment}" \
            >&2
        exit 1
    }
done

for slice_proof in \
    "${slice_equal_proof}" \
    "${slice_unequal_proof}" \
    "${slice_zero_proof}"; do
    for proof_fragment in \
        'ptr noundef captures(none) %left' \
        'ptr noundef captures(none) %right' \
        'ptr %left, ptr %right, i64 %length_frozen'; do
        rg --quiet --fixed-strings "${proof_fragment}" "${slice_proof}" || {
            echo "optimizer proof consistency: slice proof is missing ${proof_fragment}" >&2
            exit 1
        }
    done
done

for proof_fragment in \
    '%cmp = scmp i8 i64 %left, i64 %right' \
    '%is_less = icmp eq i8 %cmp, -1' \
    '%is_equal = icmp eq i8 %cmp, 0' \
    '%frozen_left = freeze i64 %left' \
    '%frozen_right = freeze i64 %right' \
    '%is_less = icmp slt i64 %frozen_left, %frozen_right' \
    '%is_equal = icmp eq i64 %frozen_left, %frozen_right' \
    '%nonless_result = select i1 %is_equal, i8 0, i8 1' \
    '%result = select i1 %is_less, i8 -1, i8 %nonless_result'; do
    rg --quiet --fixed-strings "${proof_fragment}" "${proof}" || {
        echo "optimizer proof consistency: proof is missing ${proof_fragment}" >&2
        exit 1
    }
done

for adversarial_fragment in \
    '%source_left = freeze i64 undef' \
    '%cmp = scmp i8 i64 %source_left, i64 9223372036854775807' \
    '%frozen_left = freeze i64 undef' \
    '%is_less = icmp slt i64 %frozen_left, %frozen_right' \
    '%is_equal = icmp eq i64 %frozen_left, %frozen_right'; do
    rg --quiet --fixed-strings "${adversarial_fragment}" "${undef_proof}" || {
        echo "optimizer proof consistency: undef proof is missing ${adversarial_fragment}" >&2
        exit 1
    }
done

rg --quiet --fixed-strings \
    '%unfrozen_less = icmp slt i64 undef, 9223372036854775807' \
    "${unfrozen_regression}" || {
    echo "optimizer proof consistency: unfrozen undef regression is missing" >&2
    exit 1
}

echo "optimizer proof consistency regression passed"
