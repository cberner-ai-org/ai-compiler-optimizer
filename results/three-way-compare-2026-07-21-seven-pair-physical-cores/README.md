# Seven-pair three-way comparison samples

Seven alternating baseline/candidate pairs collected on 2026-07-21 from benchmark image
`e9d0227caaace1317c72701eeb3f170ec2ca806c72ac721d0b3c569499b066c6`. The AMD EPYC-Milan host
exposes four physical cores with two SMT threads each; affinity `0,2,4,6` selected one hardware
thread per core. Four consecutive one-second samples immediately before launch reported 99-100%
idle CPU and no I/O wait.

The embedded provenance binds the candidate to pipeline `aco-three-way-compare-only`, baseline
binary SHA-256 `40bf2eb5690962e64dc3e7b42313d69b857b6ffab154b136c81524e06c0f3756`, and candidate binary
SHA-256 `7671da275b90e93be7755742e5fa21af3229887dd04885b38a6e8bcbbf8b90cf`.

- `total-times.tsv`: all 14 raw process-level monotonic wall-clock samples (SHA-256
  `be378c463ffe8702ef3e680169790e10ab290eefd34a064c3966442a0bffe4e7`).
- `phases.tsv`: all 210 raw parsed redb phase samples (SHA-256
  `da31f487f076dfb62c3560ff894872319fb7058f3e22923c86be810c3b373e26`).
- `total-summary.tsv`: paired whole-run summary.
- `phase-summary.tsv`: paired phase summaries with pointwise and family-wise confidence intervals.
- `provenance.tsv`: the immutable measured image's compiler, optimizer, wrapper, runner, source,
  and benchmark identities.
- `SHA256SUMS`: hashes for every retained input and derived report file except itself.

The non-oversubscribed four-thread phase improved 1.247% by ratio of means; paired mean speedup was
+1.771% with a pointwise 95% interval of [-10.374%, +13.915%]. The experiment does not establish a
5% improvement. See `docs/optimizations/three-way-comparison-isolation.md` for interpretation.
