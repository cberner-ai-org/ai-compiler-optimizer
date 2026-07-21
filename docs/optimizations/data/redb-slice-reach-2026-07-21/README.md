# Downstream slice-reach benchmark

This directory retains a seven-pair slice-only benchmark collected after the
matcher was extended to the exact contracts in rustc's final hot redb
monomorphizations. Execution order alternated by round and no sample was
discarded.

- image: `333a3b22d725c93e842a791f5cd8189953c98d6a7f67e1e066514b5a8fab5d4f`
- baseline SHA-256: `40bf2eb5690962e64dc3e7b42313d69b857b6ffab154b136c81524e06c0f3756`
- slice-only SHA-256: `d5ce41e886ab05ac6514f50e3479797150a24e1b8df4211a17c3b25d55bad020`
- optimizer plugin SHA-256: `75e1bce6f7653084a04c85eb640d60598742d4c7662089084fb8f900fe5e4187`
- host: Linux 6.8.0-136-generic, AMD EPYC-Milan Processor, CPUs 0-7

`total-times.tsv` and `phases.tsv` are the runner's raw process and phase
artifacts. Reproduce the two summaries with:

```console
scripts/summarize-redb-paired-totals.sh \
  docs/optimizations/data/redb-slice-reach-2026-07-21/total-times.tsv
scripts/summarize-redb-phases.sh \
  docs/optimizations/data/redb-slice-reach-2026-07-21/phases.tsv
```

The 16-thread random-read phase improved +7.613% by ratio of means and +8.061%
by paired mean, with a pointwise 95% interval of [-1.066%, +17.187%]. The full
process improved +1.366% by ratio of means. The phase point estimate clears 5%,
but its interval crosses zero; more rounds or a quieter host are needed for a
high-confidence attribution claim.
