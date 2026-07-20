# Optimization pass ablation on latest master

## Outcome

This run supersedes the earlier `ff048999` result. It uses current `origin/master` commit
`d19446f01c1f1732e618cb4a7e59f3e62722d349` and the freshly built benchmark image
`ef7fa9a83166102137992fee035d12b5624c96e8643bf18e90b3f833ea3ec192`.

The full pipeline measured a paired whole-process speedup of **+0.614%**, with a 95% confidence
interval of **[-1.006%, +2.233%]**. This run therefore does not resolve an end-to-end full-pipeline
gain or regression.

The direct marginal comparisons found:

| Added optimization | Reference -> candidate | Paired speedup | Individual 95% CI | Simultaneous 95% CI across three pass tests |
| --- | --- | ---: | ---: | ---: |
| ordered midpoint narrowing | slice -> midpoint + slice | -0.309% | [-1.520%, +0.902%] | [-1.936%, +1.318%] |
| byte-slice comparison specialization | midpoint -> midpoint + slice | -0.791% | [-2.235%, +0.654%] | [-2.732%, +1.150%] |
| signed `scmp` switch lowering | midpoint + slice -> full | +1.389% | [+0.270%, +2.508%] | [-0.114%, +2.892%] |

Signed-switch lowering is the strongest result and is positive at the individual-test 95% level
(`p = 0.0229`). It does not quite survive conservative Bonferroni correction across the three
marginal pass hypotheses (`adjusted p = 0.0686`). Midpoint and slice specialization have no
resolved whole-process effect in either their standalone or direct-addition comparisons.

The default-policy change prompted by this report keeps signed-switch lowering in `aco-passes` and
removes midpoint narrowing and slice specialization from that default. The two keyhole rewrite
families remain available through their attribution pipelines, and `aco-all-passes` preserves the
former full composition for explicit experiments. The artifact labels below describe the measured
`d19446f0` image, before that policy change.

The rebuilt signed-switch-only default was subsequently measured directly at +0.894% paired
whole-process speedup, 95% CI [+0.189%, +1.599%]. Its complete report is in
`../default-scmp-2026-07-20/`.

## Supported pipeline attribution

The measured pre-policy-change image exposed these five artifacts:

| Artifact | Midpoint | Slice/`memcmp` | Signed `scmp` switch |
| --- | --- | --- | --- |
| baseline | no | no | no |
| midpoint | yes | no | no |
| slice-comparison | no | yes | no |
| key-comparisons | yes | yes | no |
| optimized | yes | yes | yes |

The four official selector modes were each compared with baseline. Three additional adjacent,
hash-bound comparisons measured midpoint while holding slice enabled, slice while holding midpoint
enabled, and signed-switch lowering while holding both key optimizations enabled.

This is complete attribution within master's supported pipeline matrix. It is not a full `2^3`
factorial: master does not expose midpoint+signed-switch or slice+signed-switch artifacts. Therefore
the midpoint and slice marginal rows do not isolate their interaction with signed-switch lowering.
The signed-switch row is an exact full-pipeline leave-one-out comparison.

## Runtime results versus baseline

Positive values mean the candidate was faster.

| Candidate | Passes | Paired speedup | 95% CI |
| --- | --- | ---: | ---: |
| midpoint | midpoint | +0.553% | [-1.069%, +2.174%] |
| slice-comparison | slice | -0.647% | [-3.065%, +1.770%] |
| key-comparisons | midpoint + slice | -0.283% | [-0.985%, +0.419%] |
| optimized | midpoint + slice + signed-switch | +0.614% | [-1.006%, +2.233%] |

The machine's performance level moved during the overall session: per-block baseline means ranged
from 51.2 to 55.8 seconds. Comparisons are therefore interpreted only within their adjacent,
order-alternating pairs; differences between independent block means are not used as pass effects.

## Phase findings

Each experiment's phase report includes 95% paired intervals and Bonferroni familywise intervals
over its 12 reported sub-benchmarks.

- Adding midpoint to slice regressed random-range reads by -2.120%, with a within-block familywise
  interval of [-3.826%, -0.413%]. This does not survive an additional conservative correction over
  all 84 phase hypotheses from all seven experiment blocks (`adjusted p` approximately 0.119).
- The full pipeline regressed nosync writes versus baseline by -2.041%, with a within-block
  familywise interval of [-3.257%, -0.826%]. It still survives a conservative Bonferroni correction
  over all 84 phase hypotheses (`adjusted p` approximately 0.024).
- No other phase had a familywise interval excluding zero within its experiment block.

The full-pipeline nosync regression is the most robust phase-level signal and warrants targeted
reproduction before relying on the aggregate pipeline for this workload.

## Build time and binary size

These are single clean-build observations, not repeated timing experiments. Exact binary sizes are
stable; build-time percentages should be treated as descriptive because variants were built once
and sequentially.

| Variant | Clean build | Change vs baseline | Binary size | Size change |
| --- | ---: | ---: | ---: | ---: |
| baseline | 280.538 s | +0.000% | 59,765,240 B | +0 B |
| midpoint | 284.381 s | +1.370% | 59,766,664 B | +1,424 B |
| slice-comparison | 291.135 s | +3.777% | 59,768,680 B | +3,440 B |
| key-comparisons | 294.256 s | +4.890% | 59,770,096 B | +4,856 B |
| optimized | 289.187 s | +3.083% | 59,768,840 B | +3,600 B |

Marginal exact size changes are +1,416 B for midpoint when added to slice, +3,432 B for slice when
added to midpoint, and -1,256 B for signed-switch lowering when added to key-comparisons.

## Method and environment

- Seven paired rounds per comparison, with execution order alternated each round.
- Seven comparison blocks, 98 complete redb benchmark process executions total.
- Whole-process timing used `clock_gettime(CLOCK_MONOTONIC)`; phase timings came from redb output.
- Whole-process intervals use the exact two-sided Student-t critical value for six degrees of
  freedom. Phase familywise intervals use Bonferroni correction across 12 sub-benchmarks.
- Pass-level simultaneous intervals use Bonferroni correction across the three direct marginal
  comparisons (`t = 3.287455`, six degrees of freedom).
- CPU affinity: CPUs 0-7 on an 8-vCPU KVM guest, `AMD EPYC-Milan Processor`.
- Rust `8bab26f4f68e0e26f0bb7960be334d5b520ea452`, LLVM 22.1.6, redb
  `6ed1f981ba4deab0b2adbdd7bccb46ec409b2191`.
- The full repository test suite and all Alive2 proof obligations passed before measurement.
- The image build's fresh traces found 14 midpoint rewrites and six slice-order rewrites in the
  linked benchmark, and the integration gate required nonzero signed-switch rewrites. Midpoint-only
  and slice-only gates also proved the other key transform was absent.
- Free space remained at 34% after the full build and benchmark sequence.

This is a shared virtualized host, so small effects remain vulnerable to host contention. The raw
rounds, complete console logs, phase TSVs, provenance manifests, and summary TSVs are retained in
each comparison subdirectory.

## Files

- `baseline-attribution-summary.tsv`: all official modes versus baseline.
- `marginal-pass-summary.tsv`: direct pass effects, individual intervals, and three-test adjusted
  intervals/p-values.
- `artifact-summary.tsv`, `build-metrics.tsv`, and `build-metrics-summary.tsv`: artifact identities,
  clean-build measurements, and size measurements.
- `<comparison>/total-times.tsv`: raw whole-process samples.
- `<comparison>/phases.tsv`: raw parsed phase samples.
- `<comparison>/console.log`: complete benchmark and provenance output.
- `<comparison>/total-summary.tsv` and `<comparison>/subbenchmark-summary.tsv`: reproducible derived
  summaries.
- `<comparison>/provenance.tsv`: exact reference and candidate artifact hashes.
