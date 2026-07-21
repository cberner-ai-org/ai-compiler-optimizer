# Current-artifact aggregate benchmark

These are the retained process-only wall-time samples from a seven-pair run of
the final hardened aggregate artifact on 2026-07-21. The runner alternated
execution order and retained every sample.

- benchmark image: `c8fd3418d7d1fa4caa4c4d928afc61569324e1334e922ce19517c2d65054958e`
- baseline SHA-256: `40bf2eb5690962e64dc3e7b42313d69b857b6ffab154b136c81524e06c0f3756`
- optimized SHA-256: `bed73dd459949c5f7b5b68b37b053b83f67c9d63983bd9dd87f20fd834e0b37b`
- optimizer plugin SHA-256: `8e816d27461b435ec56e9ade331e234443831918b5ed9bbc3cb3d8b67e363a23`
- compiler artifact ID: `fbe353cca5525bf7a95e1c37e28f29169d3f58b23ef1fc740917ba958bab862c`
- host: Linux 6.8.0-136-generic, AMD EPYC-Milan Processor, eight effective CPUs

`total-times.tsv` is the runner's raw output. `total-summary.tsv` is reproduced
with:

```console
scripts/summarize-redb-paired-totals.sh \
  docs/optimizations/data/redb-key-comparisons-2026-07-21-current/total-times.tsv
```

The aggregate ratio of means is +1.350%. The mean paired speedup is +1.362%
with a pointwise 95% Student-t interval of [+0.024%, +2.699%]. This is direct
evidence that the current artifact modestly improves this run, but it does not
meet the repository's 5% sub-benchmark objective. The benchmark-emitted phase
means likewise did not reach 5%; the largest favorable phase point estimates
were +3.02% for the first single-thread random-read occurrence and +2.84% for
removals. Round 5 showed transient multithreaded contention and was retained.
