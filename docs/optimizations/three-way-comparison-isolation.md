# Isolated signed three-way comparison lowering

## Result

Seven alternating pairs on one hardware thread from each of four physical cores do not confirm a
5% improvement from the signed three-way comparison lowering. The non-oversubscribed four-thread
random-read phase improves 1.247% by ratio of means. Its paired mean is +1.771%, with a pointwise
95% Student-t confidence interval of [-10.374%, +13.915%] and a simultaneous family-wise interval
of [-21.546%, +25.087%]. Whole-run time regresses 0.356%, with a paired 95% interval of
[-1.219%, +0.512%].

This experiment isolates only the comparison lowering. It does not enable the midpoint or byte-slice
rewrites, removing the attribution ambiguity in earlier aggregate measurements. The longer result
supersedes the initial three-pair result and does not qualify this pass as a >=5% redb optimization.

## Transformation

Rust lowers `Ord::cmp` on signed integers to `llvm.scmp` returning `-1`, `0`, or `1`. A canonical
three-case switch on that result can require materializing the three-way value before dispatch. The
`ThreeWayCompareSwitchPass` replaces the exact i64 shape with staged comparisons:

1. freeze each operand once, preserving correlation when an input may contain `undef`;
2. branch on signed less-than;
3. on the non-less path, branch on equality; and
4. repair successor PHIs while retaining the original less, equal, and greater destinations.

The matcher requires an i8 `llvm.scmp` of i64 operands in the switch block, exactly one use, exactly
the `-1`, `0`, and `1` cases, distinct successors, and an unreachable default. Near misses remain
unchanged. The standalone pipeline name is `aco-three-way-compare-only`; `aco-passes` includes the
same pass as the performance-gated default pipeline, while default-disabled keyhole rewrites remain
available through their explicit modes.

## Safety proof

`optimizer/proofs/scmp-i64-switch-classification.opt` proves the complete staged classification as
an Alive2 refinement. `optimizer/proofs/scmp-i64-switch-undef-correlation.opt` covers the adversarial
undef case. The negative control `tests/alive2/00-scmp-i64-switch-unfrozen.opt` demonstrates that
reusing unfrozen undef operands is not equivalent and must be rejected. The proof adapter accepts
only one unqualified refinement result and rejects diagnostics, unsupported operations, timeouts,
and malformed output.

The standalone pipeline does not broaden the proof domain or alter the rewrite. Its focused test
must produce byte-identical IR to the default pipeline on the comparison fixture.

## redb reach

The clean benchmark build trace confirms transformations in the benchmark's monomorphized
`LeafAccessor::position<&[u8]>` and `BranchAccessor::child_for_key<&[u8]>` functions. It also reaches
ordered-map search code in benchmark dependencies. Every measured binary is compiled from an absent
Cargo target directory, and the runtime selector verifies the candidate mode, pipeline, binary
hashes, compiler artifacts, wrappers, clock, and runner against its embedded provenance manifest.

## Measurement

The primary experiment ran on an AMD EPYC-Milan host exposing four physical cores and two SMT
threads per core. The process was pinned to `0,2,4,6`, selecting one hardware thread from every
physical core. Immediately before launch, four consecutive one-second utilization samples reported
99-100% idle CPU and no I/O wait. Seven pairs alternated execution order. Positive speedup is
`baseline / candidate - 1`; every raw wall-time and phase sample is retained in
`results/three-way-compare-2026-07-21-seven-pair-physical-cores/`. That directory also retains the
image-bound provenance manifest reported by the runner (SHA-256 `c1b5c166...`) and a checksum index
covering the manifest, raw inputs, summaries, and README.

| Sub-benchmark | Baseline mean (ms) | Candidate mean (ms) | Aggregate speedup | Paired mean [pointwise 95% CI] | Family-wise 95% CI |
| --- | ---: | ---: | ---: | ---: | ---: |
| 4-thread random reads | 2272.714 | 2244.714 | +1.247% | +1.771% [-10.374%, +13.915%] | [-21.546%, +25.087%] |
| 8-thread random reads | 2248.286 | 2208.286 | +1.811% | +2.010% [-5.595%, +9.615%] | [-12.591%, +16.611%] |
| 16-thread random reads | 2269.714 | 2183.571 | +3.945% | +3.950% [-3.888%, +11.788%] | [-11.099%, +18.999%] |
| 32-thread random reads | 2282.714 | 2243.143 | +1.764% | +1.749% [-5.134%, +8.633%] | [-11.467%, +14.965%] |
| first single-thread random reads | 1687.857 | 1701.429 | -0.798% | -0.475% [-6.353%, +5.402%] | [-11.759%, +10.809%] |
| whole run | 56669 ms | 56872 ms | -0.356% | -0.353% [-1.219%, +0.512%] | n/a |

Only the four-thread phase has one physical core per worker. Its seven paired speedups vary from
regressions to gains, and both confidence intervals cross zero. The 8-, 16-, and 32-thread phases
oversubscribe the four-core affinity and are retained as exploratory results. No phase has a >=5%
ratio-of-means improvement, and no non-zero phase has a pointwise or family-wise interval excluding
zero.

### Superseded three-pair experiment

The earlier run pinned four adjacent logical CPUs (`2-5`) and reported +6.101% by ratio of means for
the oversubscribed 16-thread phase, with a paired mean of +6.134% and pointwise 95% interval
[+1.604%, +10.664%]. Its samples remain in `results/three-way-compare-2026-07-21/` for auditability,
but the longer, topology-aware experiment above is the primary result. The initial effect did not
reproduce.

## Build impact

In the measured image, the standalone clean build took 307.900 seconds versus 315.314 seconds for
baseline (2.351% less elapsed time). Its binary is 688 bytes smaller (59,764,552 versus 59,765,240
bytes). These are one-shot build samples, not compile-time distributions.

## Reproduction

Build and prove the repository, then select the isolated mode:

```sh
make test
make prove
make benchmark-image
./scripts/run-redb-benchmark.sh \
  --cpuset-cpus=0,2,4,6 \
  --volume "$PWD/results:/results:Z" \
  --env ACO_BENCHMARK_MODE=three-way-compare \
  --env ACO_BENCHMARK_RUNS=7 \
  --env ACO_BENCHMARK_RESULTS=/results/total-times.tsv \
  --env ACO_BENCHMARK_PHASE_RESULTS=/results/phases.tsv
```

Choose a CPU list containing one hardware thread from each physical core on the measurement host.
Summaries are reproducible with `scripts/summarize-redb-paired-totals.sh` and
`scripts/summarize-redb-phases.sh`.

## Limitations and continuation

- Seven pairs provide six degrees of freedom, but the four-thread paired variance remains high.
- This host has only four physical cores. It can control the four-thread endpoint without SMT
  sharing, but the 8-, 16-, and 32-thread results remain oversubscribed.
- The earlier 16-thread >5% point estimate did not reproduce under the longer protocol.
- The pass is already part of the aggregate optimizer. This work establishes independent reach and
  impact rather than introducing a new semantic rewrite.
- Further work toward the project goal should profile a distinct hot pattern rather than treating
  this lowering as the qualifying optimization.
