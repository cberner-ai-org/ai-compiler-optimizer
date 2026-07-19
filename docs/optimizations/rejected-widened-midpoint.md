# Rejected widened unsigned midpoint candidate

## Status

This broad known-bits candidate was investigated and rejected. Alive2 did not return an
unqualified refinement proof within the configured deadline, so the repository's fail-closed
policy requires rejection regardless of the algebraic argument. A distinct, narrower rewrite for
ordered binary-search loops was later proved and integrated; see
[`redb-key-comparisons.md`](redb-key-comparisons.md). It relies on CFG-proven `minimum < maximum`,
not the rejected upper-32-bits-known-zero condition.

## Workload observation

redb performs binary searches in `LeafAccessor::position` and `BranchAccessor::child_for_key`.
On a 64-bit target, Rust's `usize::midpoint` expands through a widened unsigned calculation:

```llvm
%left.wide = zext i64 %left to i128
%right.wide = zext i64 %right to i128
%sum = add i128 %left.wide, %right.wide
%half = lshr i128 %sum, 1
%result = trunc i128 %half to i64
```

An optimized LLVM 20 IR build of pinned redb 4.1.0 contained 20 instances of this shape, including
leaf and branch search specializations. This host-compiler inventory is candidate-discovery
evidence, not benchmark provenance: the exact count must be regenerated from the pinned LLVM 22
stage-1 compiler before relying on it. `scripts/find-widened-midpoints.sh` records each occurrence
with its function, LLVM IR line, and native operands so future investigations can reproduce the
inventory instead of depending on a one-off search.

## Proposed rewrite

When both native operands are known to fit in 32 bits, their sum cannot overflow `i64`. The widened
sequence could therefore be narrowed to:

```llvm
%sum = add i64 %left, %right
%result = lshr i64 %sum, 1
```

The intended matcher used LLVM known-bits analysis and required the upper 32 bits of both operands
to be known zero. That condition is stronger than merely checking the sign bit and is expected for
redb's search bounds, which originate from 16-bit page entry counts.

On x86-64, the existing widened form is selected as the Hacker's Delight average sequence (`and`,
`xor`, shift, add). The proposed result would use only add and shift. That instruction-count
reduction motivated the candidate, but it was not benchmarked because proof is an earlier mandatory
gate.

## Proof result

The obligation modeled 32-bit values zero-extended to `i64`, followed by the exact `i64`/`i128`
source and native target. The pinned Alive2 revision timed out under the then-configured 10-second
SMT deadline. Diagnostic reruns with larger bounds also failed to produce a proof; one run remained in
the solver beyond 100 seconds and was stopped. A timeout is a failed proof, not evidence of safety.

No proof file or C++ matcher for this known-bits candidate is retained under `optimizer/`,
preventing a later build from mistaking it for the accepted ordered-loop rewrite.

## Impact

There is no isolated performance claim for this rejected form. Its useful outcome is a reproducible
inventory check and a documented negative result. It must not be revived on an algebraic argument
alone; any broader matcher still needs its own unconditional proof.
