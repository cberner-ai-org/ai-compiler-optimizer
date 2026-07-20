# Signed-switch-only default benchmark

## Outcome

This is the direct follow-up to `results/pass-ablation-master-2026-07-20/`. It measures the rebuilt
performance-gated default after midpoint narrowing and slice-comparison specialization were removed
from `aco-passes`. The candidate therefore contains signed `llvm.scmp` switch lowering only.

Across seven alternating baseline/candidate pairs, the candidate's paired mean whole-process
speedup was **+0.894%**, with a two-sided 95% Student-t confidence interval of
**[+0.189%, +1.599%]**. All seven paired estimates were positive. The aggregate ratio of arithmetic
means was +0.892% (51.212 s baseline versus 50.760 s candidate).

This resolves a positive effect at the predeclared whole-process endpoint in this run. It confirms
the direction of the prior leave-one-pass-out result (+1.389% [+0.270%, +2.508%]) without including
either default-disabled keyhole rewrite. The effect is still below the repository's original 5%
objective, and this shared virtualized host remains a source of scheduling noise.

## Phase results

The phase summary reports pointwise intervals and Bonferroni family-wise intervals across all 12
redb endpoints. No phase has a family-wise-significant regression.

- Bulk load improved by +1.805% paired mean, with a family-wise 95% interval of
  [+0.062%, +3.547%].
- Four-thread random reads improved by +1.302%; its pointwise interval is
  [+0.521%, +2.082%], but its family-wise interval includes zero.
- Compaction had the largest negative point estimate at -0.798%; its pointwise interval
  [-1.731%, +0.135%] includes zero.
- Higher-thread-count reads were visibly noisy in both directions. No sample was discarded or
  rerun.

The phase findings are secondary. The whole-process endpoint was predeclared by the direct-default
follow-up and is the basis of the performance conclusion.

## Build time and binary size

These are single clean-build observations; build time is descriptive, while file size is exact.

| Variant | Clean build | Change vs baseline | Binary size | Size change |
| --- | ---: | ---: | ---: | ---: |
| baseline | 275.566 s | +0.000% | 59,765,240 B | +0 B |
| signed-switch default | 275.544 s | -0.008% | 59,764,552 B | -688 B (-0.001%) |

The image also rebuilt the opt-in attribution artifacts: midpoint at 276.774 s / 59,766,664 B,
slice comparison at 278.553 s / 59,768,680 B, and combined key comparisons at
280.340 s / 59,770,096 B.

## Integration and provenance

- Benchmark image:
  `bad4dc74dfe0d2ce79f91fd97090b5b90351fe159f56ae6f2575cbefd37bdd5e`.
- Base repository commit: `d19446f01c1f1732e618cb4a7e59f3e62722d349`, plus the reported
  signed-switch-only default-policy changes.
- Pipeline: `optimized` -> `aco-passes` -> signed-switch lowering only.
- The fresh redb boundary probe found two signed-switch transforming traces and no keyhole trace.
- The clean optimized benchmark build found nonzero signed-switch transformations, including redb's
  `LeafAccessor::position` and `BranchAccessor::child_for_key` specializations, and no keyhole trace.
- Baseline SHA-256:
  `40bf2eb5690962e64dc3e7b42313d69b857b6ffab154b136c81524e06c0f3756`.
- Candidate SHA-256:
  `7671da275b90e93be7755742e5fa21af3229887dd04885b38a6e8bcbbf8b90cf`.
- CPU affinity: CPUs 0-7 on an eight-vCPU KVM guest, `AMD EPYC-Milan Processor`.
- Rust `8bab26f4f68e0e26f0bb7960be334d5b520ea452`, LLVM 22.1.6, redb
  `6ed1f981ba4deab0b2adbdd7bccb46ec409b2191`.
- Timing: `clock_gettime(CLOCK_MONOTONIC)` around each complete benchmark process.
- The full repository checks, all Alive2 obligations, both sets of 37 redb tests, and the benchmark
  image's embedded smoke and trace checks passed before measurement.

## Files

- `total-times.tsv`: 14 raw complete-process samples.
- `total-summary.tsv`: paired whole-process statistics.
- `phases.tsv`: 210 structured phase samples written directly by the runner.
- `phase-log.txt`: a lossless log-shaped projection of `phases.tsv` for the existing phase
  summarizer; it is derived data, not an independent measurement source.
- `subbenchmark-summary.tsv`: pointwise and 12-endpoint family-wise paired phase statistics.
- `provenance.tsv`: image-bound compiler, pipeline, source, and executable identities.
- `build-metrics.tsv` and `build-metrics-summary.tsv`: clean-build duration and exact binary size.
- `SHA256SUMS`: hashes for every retained input and derived report file except itself.
