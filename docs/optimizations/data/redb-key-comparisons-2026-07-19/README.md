# redb key-comparison attribution data

These are the retained inputs and generated summaries for the seven-pair
2026-07-19 experiment documented in
[`redb-key-comparisons.md`](../../redb-key-comparisons.md).

Each mode directory contains:

- `console.log`: machine metadata, complete provenance, labeled benchmark
  output, and the runner's aggregate tables;
- `total-times.tsv`: legacy pre-fix whole-run samples retained for audit only;
- `phases.tsv`: every parsed phase sample;
- `total-summary.tsv`: reproducible summary of the legacy whole-run samples;
  and
- `subbench-summary.tsv`: paired pointwise and Bonferroni family-wise
  sub-benchmark intervals.

The seven-pair runner took its start timestamp before creating the output
capture and its finish timestamp after parsing phase rows and removing that
capture. Consequently the `total-*` files include harness and filesystem work
and are not valid process-only performance evidence. They remain unchanged so
their derivation can be audited. The phase samples were emitted by redb and are
unaffected. The current runner brackets only the benchmark process pipeline;
a new long run would be required to replace the legacy whole-run intervals.

`build-metrics.tsv` was regenerated from final hardened benchmark image
`1471fb6f84d8ee355ae49bb398e7a44d8a5d7ba1219b9999bf492d9849e4cdcc`.
Every measured mode started with an absent target directory and deleted it
after installation; only the checksum-verified Cargo registry was shared.
`build-metrics-summary.tsv` compares each row with the baseline. Build elapsed
time is a single sequential clean-target observation, not a confidence
interval.

The seven-pair runtime logs came from image
`89523badf45cba9afb12a7e08fd1ab6b9f12c8a996c71ab8ac1d2f8c696df671`.
The final control-contract hardening changed the slice-only hash from
`9f7e578a...` to `85a5acf0...` and the combined/aggregate hash from
`49f63153...` to `eaaaa0ab...`. Baseline (`40bf2eb5...`) and midpoint
(`2c9c6fe6...`) are unchanged. The retained seven-pair phase samples therefore
remain an auditable pre-hardening attribution experiment, but they are not
exact current-artifact measurements. A new long run is required for current
slice and combined performance claims.

`attribution-summary.tsv` gathers the valid primary random-read rows and labels
the copied pre-fix whole-run rows with a `legacy_harness_total_` prefix.

The seven-pair `optimized` and `key-comparisons` benchmark files had the same
SHA-256 (`49f63153ad01c4d6addb0d7b74b6de0b3e5f66566fbaafdd96757f7e5c4c9253`),
so no duplicate `optimized` runtime block was collected. Their final hardened
replacements are also identical to one another, at SHA-256
`eaaaa0ab445fb41b0d5dc943ca183a60ffae5b9b4eb0e007bd0ecb46d8dfcc3a`.
