#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
implementation="${repo_root}/optimizer/OptimizerPlugin.cpp"
proof="${repo_root}/optimizer/proofs/scmp-i64-switch-classification.opt"
undef_proof="${repo_root}/optimizer/proofs/scmp-i64-switch-undef-correlation.opt"
unfrozen_regression="${repo_root}/tests/alive2/00-scmp-i64-switch-unfrozen.opt"

for implementation_fragment in \
    'Intrinsic::scmp' \
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
