# Three-way comparison isolation samples

> Superseded by the seven-pair, topology-aware experiment in
> `results/three-way-compare-2026-07-21-seven-pair-physical-cores/`. These samples remain for
> auditability and are not the report's primary result.

Three alternating baseline/candidate pairs collected on 2026-07-21 from benchmark image
`8f8566cc9c3114771e55cb927f6d4823c4b111073a8264f3249facd71d0cdaa9` with effective CPU affinity
`2-5`. The candidate is provenance-bound to `aco-three-way-compare-only`.

- `total-times.tsv`: process-level wall-clock samples.
- `phases.tsv`: every parsed redb phase sample.
- `total-summary.tsv`: paired whole-run summary.
- `phase-summary.tsv`: paired sub-benchmark summary and confidence intervals.

The 16-thread random-read phase improved 6.101% by ratio of means and 6.134% by paired mean, with a
pointwise 95% confidence interval of [+1.604%, +10.664%]. See
`docs/optimizations/three-way-comparison-isolation.md` for interpretation and limitations.
