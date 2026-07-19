#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
implementation="${repo_root}/optimizer/OptimizerPlugin.cpp"
proof="${repo_root}/optimizer/proofs/scmp-i64-switch-classification.opt"
undef_proof="${repo_root}/optimizer/proofs/scmp-i64-switch-undef-correlation.opt"
unfrozen_regression="${repo_root}/tests/alive2/00-scmp-i64-switch-unfrozen.opt"
memcmp_proof="${repo_root}/optimizer/proofs/memcmp-first-byte.srctgt.ll"

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
    'Call.isConvergent()' \
    'Call.isMustTailCall()' \
    'Call.getTailCallKind() == llvm::CallInst::TCK_NoTail' \
    'Call.getCallingConv() != llvm::CallingConv::C' \
    'Call.hasOperandBundles()' \
    'Call.hasFnAttr(llvm::Attribute::NoReturn)' \
    'Call.hasFnAttr(llvm::Attribute::ReturnsTwice)' \
    'Call.hasFnAttr(llvm::Attribute::NoDuplicate)' \
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

for proof_fragment in \
    'target datalayout = "e-p:64:64:64"' \
    'define i32 @src(ptr captures(none) %left, ptr captures(none) %right, i64 %length)' \
    '%result = call i32 @memcmp(ptr %left, ptr %right, i64 %length)' \
    'define i32 @tgt(ptr captures(none) %left, ptr captures(none) %right, i64 %length)' \
    'declare i32 @memcmp(ptr captures(none), ptr captures(none), i64)'; do
    rg --quiet --fixed-strings "${proof_fragment}" "${memcmp_proof}" || {
        echo "optimizer proof consistency: memcmp proof is missing ${proof_fragment}" >&2
        exit 1
    }
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
