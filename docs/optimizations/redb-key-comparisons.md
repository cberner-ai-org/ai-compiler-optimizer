# redb key-comparison keyhole pass

## Summary

Safety status: accepted on 2026-07-19. Performance status: disabled by default
on 2026-07-20. A seven-pair exact-artifact ablation on current master found
negative marginal whole-process point estimates for both keyhole rewrite
families and a robust nosync-write regression in the former full pipeline.

The LLVM 22 `KeyholePass` specializes two operations in redb's B-tree lookup
path:

1. It replaces a widened unsigned midpoint in an ordered binary-search loop
   with `minimum + ((maximum - minimum) >> 1)` at native width.
2. It checks the first byte before a `memcmp`-based byte-slice comparison. When
   those bytes differ, it returns their ordering directly and skips both libc
   and the later sign-normalization chain.

Both transformations have exact, fail-closed Alive2 refinement proofs and
focused positive, near-miss, mode-isolation, and idempotence tests. They remain
available through midpoint-only, slice-only, combined-key, and explicit
all-passes pipelines, but are not scheduled by `aco-passes`.

The latest study used exact hardened benchmark artifacts, seven alternating
pairs per comparison, corrected process-only timing, and complete provenance:

| Comparison | Paired whole-process speedup | 95% CI |
| --- | ---: | ---: |
| midpoint vs baseline | +0.553% | [-1.069%, +2.174%] |
| slice vs baseline | -0.647% | [-3.065%, +1.770%] |
| midpoint + slice vs baseline | -0.283% | [-0.985%, +0.419%] |
| add midpoint while holding slice enabled | -0.309% | [-1.520%, +0.902%] |
| add slice while holding midpoint enabled | -0.791% | [-2.235%, +0.654%] |

Neither individual keyhole effect is statistically resolved, but both direct
marginal point estimates are negative. In addition, the former full pipeline
regressed nosync writes by -2.041%, with a 12-endpoint family-wise 95% interval
of [-3.257%, -0.826%]; that signal also survives a conservative Bonferroni
correction over all 84 inspected phase hypotheses (adjusted `p` approximately
0.024). Keeping these rewrites opt-in avoids spending default compile time and
code size on transformations without positive workload evidence.

## Motivation and workload location

redb searches leaf and branch pages by comparing byte keys while narrowing a
`[minimum, maximum)` interval. Pinned rustc lowers `usize::midpoint` through
zero-extension to `i128`, addition, shift, and truncation. It lowers Rust slice
ordering to `llvm.umin`, libc `memcmp`, a length tie-break, and `llvm.scmp`.

The benchmark image's build-time traces found 14 midpoint rewrites in the
midpoint-only artifact. The slice-only artifact found slice-order rewrites
throughout the linked benchmark and, specifically, in the hot
`LeafAccessor::position` and `BranchAccessor::child_for_key` specializations.
The combined and aggregate builds required both rewrite families in those hot
specializations. Mode gates also required zero slice rewrites in midpoint-only
and zero midpoint rewrites in slice-only, so an attribution binary cannot
silently contain the other key optimization.

## Selectable pipelines

The plugin exposes five strict pipeline names:

| Pipeline | Midpoint | Slice/`memcmp` | signed `scmp` switch |
| --- | :---: | :---: | :---: |
| `aco-midpoint-only` | yes | no | no |
| `aco-slice-comparison-only` | no | yes | no |
| `aco-key-comparisons` | yes | yes | no |
| `aco-passes` | no | no | yes |
| `aco-all-passes` | yes | yes | yes |

In the explicit `aco-all-passes` pipeline, the keyhole pass runs before
signed-switch lowering. This ordering is required:
the slice matcher consumes an exact `llvm.scmp` use chain, so lowering that
intrinsic first makes the aggregate pipeline miss a separately proved rewrite.
The focused structural test contains a slice ordering immediately consumed by a
switch and rejects an aggregate output containing `aco.scmp.nonless` in that
function.

`ACO_OPTIMIZER_PIPELINE` and `ACO_BENCHMARK_MODE` use fail-closed allowlists.
The provenance writer and runtime selector independently enforce the exact
mode-to-pipeline mapping, including `midpoint` to `aco-midpoint-only` and
`slice-comparison` to `aco-slice-comparison-only`; a missing or merely
allowlisted-but-wrong pipeline is rejected. Each compiler mode has a separate
identity. The runtime selector binds the chosen executable, pipeline, selector
hash, and provenance manifest before running the common baseline/candidate
harness.

## Ordered midpoint rewrite

The source shape is:

```llvm
%minimum.wide = zext i64 %minimum to i128
%maximum.wide = zext i64 %maximum to i128
%sum.wide = add nuw nsw i128 %minimum.wide, %maximum.wide
%half.wide = lshr i128 %sum.wide, 1
%midpoint = trunc nuw i128 %half.wide to i64
```

The replacement is:

```llvm
%delta = sub nuw i64 %maximum, %minimum
%half.delta = lshr i64 %delta, 1
%midpoint = add nuw i64 %minimum, %half.delta
```

The matcher accepts only the exact two-PHI binary-search loop where:

- the narrowing cast is `trunc nuw i128 ... to i64` without `nsw`;
- the initial minimum is zero;
- entry is guarded by a nonzero initial maximum, directly or through a
  one-block preheader;
- the backedge minimum is unchanged or `midpoint + 1`;
- the backedge maximum is unchanged or `midpoint`; and
- the backedge returns only on unsigned `next_minimum < next_maximum`.

Those CFG conditions establish `minimum < maximum` whenever the midpoint is
evaluated. The native subtraction and final addition therefore cannot wrap,
which justifies the emitted `nuw` flags. The replacement reduces the selected
x86-64 midpoint sequence from four arithmetic operations (`and`, `xor`, shift,
add) to three (`sub`, shift, add).

This is intentionally different from the rejected known-bits candidate in
[`rejected-widened-midpoint.md`](rejected-widened-midpoint.md).

## First-byte comparison rewrite

For a general three-argument libc `memcmp`, the pass freezes both pointer
operands and the length, checks that the length is nonzero, loads and freezes
byte zero from each frozen pointer, and calls libc with the same frozen
pointers only when the bytes are equal. The pointer freezes ensure an
undef-producing source operand selects one address shared by the new load and
retained call. If the bytes differ, zero-extension and `sub nsw` produce an
exact valid `memcmp` result. Zero length returns zero without loading memory.
`isProvenMemcmpCall` owns the tracked ABI/type domain: little-endian 64-bit
address-space-zero pointers and an `i64` length.
`hasUnsupportedCallControlContract` separately owns the placement contract for
both calls relocated by specialization. It rejects non-C conventions, operand
bundles, convergence, mandatory or prohibited tail placement, and
control-sensitive function attributes. An ordinary `tail` marker is only a
discardable hint and is cleared from either relocated call. Memory effects on
both the call and declaration must permit argument-memory reads. One refinement
obligation covers calls without return or parameter contracts; a second covers
Rust's exact call shape with `nonnull` on both pointer operands. Every other
call-site return or parameter contract is rejected, and the declaration may
carry only its capture parameter contract. The callee must be an external libc
declaration rather than a module-local body. Non-debug call metadata is
rejected because it can constrain a bypassed result or memory access.

redb's hot slice-order shape is more specific:

```llvm
%length = call i64 @llvm.umin.i64(i64 %left.len, i64 %right.len)
%comparison = call i32 @memcmp(ptr %left, ptr %right, i64 %length)
%extended = sext i32 %comparison to i64
%equal = icmp eq i32 %comparison, 0
%length.diff = sub i64 %left.len, %right.len
%difference = select i1 %equal, i64 %length.diff, i64 %extended
%ordering = call i8 @llvm.scmp.i8.i64(i64 %difference, i64 0)
```

On unequal first bytes, the specialized path computes an unsigned byte
comparison and selects `-1` or `1`. Equal bytes and zero lengths retain the
original `memcmp`, length tie-break, and signed comparison. Matcher checks
require exactly the `sext`/zero equality/select/`llvm.scmp.i8.i64` use chain in
one block. Both the intrinsic ID and exact overload name are checked. The
ordering call must have no return or parameter contracts; any materialized
declaration contracts must equal LLVM's canonical intrinsic attributes, and
non-debug metadata is rejected. Any unrelated instructions interleaved between
`memcmp` and `llvm.scmp` are sunk, in order, to the shared continuation rather
than moved into the slow block. Thus calls, stores, and other work remain
unconditional on both fast and slow paths instead of being bypassed when the
first bytes differ.

The transformed slow call carries `!aco.expanded` metadata. A second pass run
therefore performs no further expansion. The focused driver runs every
selectable pipeline twice and checks that each fixture still has exactly one
fast-path CFG.

## Alive2 safety argument

`make prove` builds pinned Alive2 commit
`1d1bc4fe3135492a8c1166838c776530de479420` against the same LLVM 22.1.6 used by
the stage-1 compiler. The tracked compatibility patch only updates APIs needed
to build `alive-tv`; it does not relax proof acceptance. The gate allows 60
seconds per SMT query, 90 seconds per process, and 1 GiB of solver memory. A
timeout, diagnostic, unsupported operation, counterexample, or anything other
than one unqualified refinement result fails. Exact-LLVM checks use
`-fail-src-ub`; stderr must be empty, and stdout must contain one success result
without any Alive2 warning, error, note, or unsupported-operation record.

The keyhole obligations are:

- `narrow-ordered-midpoint.srctgt.ll`: exact widened source and native target
  under the matcher's unsigned ordering precondition;
- `single-use-pointer-freeze.srctgt.ll`: replacing either source pointer's one
  use with a frozen value is a refinement; applying it to both operands creates
  the correlated, `noundef` intermediate used by the remaining obligations;
- `memcmp-first-byte.srctgt.ll`: complete zero/equal/unequal expansion,
  including correlated pointer and length freezes, loads, memory behavior, and
  the libc model over that `noundef` pointer intermediate;
- `memcmp-first-byte-call-attrs.srctgt.ll`: the same expansion with Rust's exact
  two-pointer `nonnull` call contract and `argmem: read` effects;
- `slice-order-zero-after-memcmp-expansion.srctgt.ll`: zero frozen length;
- `slice-order-equal-after-memcmp-expansion.srctgt.ll`: nonzero length and
  equal frozen first bytes; and
- `slice-order-unequal-after-memcmp-expansion.srctgt.ll`: nonzero length and
  unequal frozen first bytes, including direct `-1`/`1` ordering.

The final three conditions are mutually exclusive and exhaustive. They prove
the specialized fold after the independently proved generic expansion. The
equivalent monolithic query exceeded the deadline and was rejected; it is not
an accepted proof.

The complete suite has ten accepted obligations: these seven, two signed
comparison obligations, and the identity gate smoke. The final `make prove`
completed every obligation without timeout or diagnostic and still rejected
the known-inequivalent and unfrozen negative controls.

## Tests and integration checks

- `optimizer/tests/keyhole-input.ll` contains an ordered-loop positive case, an
  unguarded near miss, generic `memcmp`, the slice-order shape, an immediate
  slice-order switch interaction, and an adversarial interleaved side-effecting
  call that must remain in the shared continuation after specialization. It
  also contains `convergent`, `musttail`, and `notail` memcmp calls that must
  remain unchanged.
- Signed-wrap midpoint fixtures preserve both `trunc nsw` and `trunc nuw nsw`
  near misses, binding the matcher to the exact `trunc nuw` source proved by
  Alive2.
- `optimizer/tests/keyhole-unproved-memcmp-input.ll` exercises the unproved
  i686/i32 ABI and verifies that no memcmp expansion is emitted.
- `optimizer/tests/keyhole-constrained-ordering-input.ll` contains
  verifier-valid `musttail`, `notail`, convergent, and ordinary-tail
  `llvm.scmp` calls. The public plugin runs it under `-verify-each`, leaves the
  three contracted ordering chains unspecialized, and specializes the ordinary
  hint only after clearing it.
- API-level and verifier-backed ordering-contract fixtures reject fake
  intrinsic names, call-site return and parameter attributes, and result
  metadata. LLVM's parser canonicalizes textual intrinsic suffixes, so the
  structural driver renames the verified fixture through LLVM's API before
  checking that the exact-name guard remains fail closed.
- The argument- and memory-contract fixtures run under `-verify-each`, reject
  partial `nonnull`, `noundef`, dereferenceability, alignment, read-write or
  non-argument call/declaration memory effects, and retain the exact
  two-pointer `nonnull` and `argmem: read` cases. A separate relocation fixture
  rejects an interleaved `convergent` call while the ordinary side-effect case
  remains in the shared continuation.
- Additional fixtures leave result-constraining `memcmp` metadata and a
  module-defined `memcmp` body untouched. An explicit `ptr undef` positive case
  checks that both generated loads and the retained call share each frozen
  pointer value.
- `optimizer/test.sh` tests all five pipelines through the real LLVM 22 plugin
  and a linked structural driver, runs each keyhole pipeline twice, checks exact
  transform counts, preserves the near miss, and checks idempotence.
- Wrapper tests check the strict pipeline allowlist, per-mode environment, and
  separate artifact identities.
- Selector and provenance tests bind each runtime mode to its executable and
  exact pipeline, propagate one relocated binary root to the candidate,
  baseline, and monotonic clock, and reject unknown, missing, or mismatched
  mappings.
- The toolchain image compiles and runs a Rust slice-ordering smoke with and
  without the plugin and rejects midpoint or slice-specialization markers in
  default optimized IR. The fresh redb probe separately requires signed-switch
  lowering.
- The redb image ran all 37 library tests independently in baseline and
  optimized modes. Both sets passed.
- The benchmark image linked all five artifacts, checked all mode-specific
  traces, and rejected invalid selector invocations before being tagged.
- Final review-hardened image `f5eaafb32f45...` completed a one-pair runtime
  smoke with exact `optimized` to `aco-passes` provenance, clean exits, and all
  15 phase rows. Its 53.882 s versus 52.505 s process-only sample is a plumbing
  check, not statistical performance evidence.
- Statistical regressions validate exact pointwise sub-benchmark and
  12-endpoint Bonferroni intervals, reproduce the legacy seven-pair whole-run
  audit summaries, and verify that current wall timers exclude output setup,
  phase extraction, and cleanup.
- Proof-gate regressions model Alive2's stdout always-UB warning and require
  both diagnostic rejection and the `-fail-src-ub` verifier option.

## Historical pre-hardening seven-pair attribution experiment

### Method

The experiment used pinned Rust 1.97.1 commit
`8bab26f4f68e0e26f0bb7960be334d5b520ea452`, redb 4.1.0 commit
`6ed1f981ba4deab0b2adbdd7bccb46ec409b2191`, the tracked Cargo lockfile, and the
digest-pinned Bookworm image with Debian snapshot `20260713T000000Z`.

Image
`89523badf45cba9afb12a7e08fd1ab6b9f12c8a996c71ab8ac1d2f8c696df671`
ran on Linux 6.8.0-124-generic under KVM on an AMD EPYC-Milan processor. All
eight online CPUs (0-7) were the effective affinity. One `make benchmark` pair
served as an excluded integration warm-up. Three retained mode blocks then ran
in midpoint, slice, and combined order. Each block used seven pairs and
alternated variant order each round.

The predeclared primary endpoint is `random_reads`: the average of redb's two
one-million-item single-thread random-read iterations within each variant and
round. Positive speedup is `baseline / candidate - 1`. The report gives the
mean of seven paired speedups and a two-sided 95% Student-t interval with six
degrees of freedom. Twelve redb endpoints were also inspected, so retained TSVs
include Bonferroni family-wise 95% intervals. Whole-run elapsed time uses the
same paired pointwise calculation in current experiments.

The retained seven-pair runner predated the corrected timer boundary: its start
timestamp was taken before capture-file creation and its finish timestamp after
phase parsing and temporary-file removal. Its `total-times.tsv` and derived
whole-run intervals therefore include harness and mounted-filesystem work and
are retained only as an audit trail. They are not used as performance evidence.
The benchmark-emitted phase rows, including the predeclared `random_reads`
endpoint, are unaffected. The corrected runner creates the capture file first
and records completion immediately after the process pipeline and status
checks, before parsing or cleanup; a functional regression checks both edges.

Host load was checked before every block. The machine was 97-99% idle before
midpoint and mostly idle before the later blocks, but bursty contention appeared
during retained slice and combined rounds. No sample was discarded or rerun.
The wide intervals honestly reflect that limitation.

### Primary results and legacy whole-run audit

The random-read columns below are valid benchmark-emitted phase measurements.
The final two columns reproduce the contaminated pre-fix whole-run samples for
transparency only; they are not process-only timings or acceptance evidence.

| Mode | Random-read baseline / candidate mean (ms) | Paired read mean [95% CI] | Read median | Legacy whole-run baseline / candidate mean (s) | Legacy paired whole-run mean [95% CI] |
| --- | ---: | ---: | ---: | ---: | ---: |
| midpoint | 1611.4 / 1626.9 | -0.82% [-4.06%, +2.42%] | -0.19% | 51.320 / 51.044 | +0.54% [-0.48%, +1.57%] |
| slice comparison | 1663.4 / 1663.4 | +0.34% [-7.57%, +8.24%] | -0.19% | 52.648 / 54.073 | -2.10% [-7.75%, +3.56%] |
| midpoint + slice | 1685.9 / 1669.4 | +1.65% [-9.19%, +12.50%] | +0.92% | 53.466 / 52.417 | +1.98% [-3.31%, +7.27%] |

The corresponding aggregate ratios of arithmetic means are -0.96%, +0.00%,
and +0.99% for primary reads. They differ slightly from the paired means because
rounds have different absolute durations. Neither form supports a 5% claim.

The family-wise intervals for primary reads are [-6.77%, +5.12%],
[-14.16%, +14.83%], and [-18.23%, +21.53%], respectively. They are included to
prevent selecting another favorable endpoint from the same 12-row table.

All raw output, valid phase samples, legacy whole-run audit samples, generated
summaries, and data-format notes are retained in
[`data/redb-key-comparisons-2026-07-19/`](data/redb-key-comparisons-2026-07-19/README.md).

### Attribution conclusion

Midpoint-only has the narrowest interval and is consistent with no practical
effect on the primary endpoint. Slice-only is also centered near zero but is
much noisier. The combined point estimate is positive, but its interval spans a
large regression and a large improvement. It does not establish either an
additive or synergistic interaction.

The seven-pair `optimized` and `key-comparisons` benchmark files were
byte-for-byte identical at SHA-256
`49f63153ad01c4d6addb0d7b74b6de0b3e5f66566fbaafdd96757f7e5c4c9253`.
Consequently the combined seven-pair result also measures the exact aggregate
runtime artifact; collecting a duplicate optimized block would add no binary
contrast.

Final review-hardened clean-target image
`f5eaafb32f45870aa867ecca903ec6c1a66b59251a94d19da7ccbbb9fd819596`
retained the baseline `40bf2eb5...` and midpoint `2c9c6fe6...` hashes. The final
call-contract, metadata, callee-identity, and pointer-correlation boundary
produced slice-only `3c0d4f64...`, combined `b7d9caae...`, and aggregate
`bed73dd4...` artifacts.
The historical phase confidence intervals still audit the attribution study,
but they are not exact measurements of the final slice-containing artifacts.
No current-artifact performance claim is made from those historical samples.
The exact-artifact 2026-07-20 ablation reported in the summary resolves this
specific limitation; it does not repair the older samples.

The original five-pair experiment used baseline hash
`40bf2eb5690962e64dc3e7b42313d69b857b6ffab154b136c81524e06c0f3756`
and combined hash
`49f63153ad01c4d6addb0d7b74b6de0b3e5f66566fbaafdd96757f7e5c4c9253`—the
same exact files used here. Its favorable 6.09% and 9.63% per-iteration ratios
had no confidence interval and are superseded as acceptance evidence by this
longer attribution study.

## Current code size and compile-time impact

The benchmark image records full executable file size and wall time for each
separate `cargo bench --no-run` build. Every mode started with an absent
isolated target directory and removed it after installing the Cargo-reported
executable; the target was not a persistent Podman cache.

| Mode | Build time | Change vs baseline | File size | Size change |
| --- | ---: | ---: | ---: | ---: |
| baseline | 275.566 s | — | 59,765,240 B | — |
| midpoint | 276.774 s | +0.44% | 59,766,664 B | +1,424 B (+0.002%) |
| slice comparison | 278.553 s | +1.08% | 59,768,680 B | +3,440 B (+0.006%) |
| midpoint + slice | 280.340 s | +1.73% | 59,770,096 B | +4,856 B (+0.008%) |
| signed-switch default | 275.544 s | -0.01% | 59,764,552 B | -688 B (-0.001%) |

Compile times are one sequential observation per mode, not paired samples. They
include all locked benchmark dependencies and are affected by host scheduling,
filesystem cache state, and build order. Candidate differences range from
+0.44% to +1.73% for the keyhole artifacts, so none of these one-shot values can
be attributed to pass cost. Their deterministic observation is
0.002%-0.008% code-size growth; the signed-switch-only default instead shrinks
the binary by 688 bytes. Independent randomized compile-time pairs would be
needed for a timing interval.

## Limitations and follow-up

- The pass recognizes exact rustc LLVM 22 shapes and fixed i64/i128 types; it is
  not a general midpoint or lexicographic-comparison canonicalizer.
- Equal byte prefixes still pay two loads and a branch before libc. This may
  offset the unequal-first-byte fast path for some key distributions.
- Runtime blocks were paired and started after idle checks, but shared-host
  contention remained visible. A dedicated host and substantially more
  randomized pairs are required before making another performance claim.
- The 2026-07-20 ablation supplies corrected process-only confidence intervals
  for exact hardened artifacts. Its complete raw data and provenance are in
  `results/pass-ablation-master-2026-07-20/`.
- Compile-time values are descriptive single observations and have no
  confidence interval.
- The next optimization candidate should not rely on this pass to satisfy the
  repository's 5% objective. Keep the safety work, but profile a different hot
  pattern or revise this matcher only after new controlled evidence.
