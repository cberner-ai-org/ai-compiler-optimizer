# Signed three-way comparison switch optimization

## Outcome

The custom LLVM function pass lowers a canonical `llvm.scmp.i8.i64`
three-way switch to direct signed less-than and equality branches. It targets
comparison classification in redb's B-tree search loops, where Rust otherwise
normalizes an integer comparison to `-1`, `0`, or `1` and immediately switches
on that normalized value.

Safety is established: pinned Alive2 proves the staged route with each reused
operand frozen once, including an explicit `undef` versus `INT64_MAX`
obligation. The LLVM regression checks reuse of those exact frozen SSA values,
the complete less/equal/greater destination mapping, and PHI repair. The
benchmark image also compiles a real redb byte-slice probe from separate fresh
baseline and optimized target directories; baseline must emit no ACO trace,
while optimized must emit a transforming trace.

There is currently no retained repeated experiment that satisfies the final
provenance scheme. A seven-pair historical diagnostic observed the
pass-sensitive single-thread random-read sub-benchmark improve from 2100.357 ms
to 1959.429 ms, an aggregate **7.192%**, but it hashed the rustup proxy instead
of the selected Cargo executable. Its pointwise 95% interval was -5.306% to
+20.090%, its 12-endpoint family-wise interval was -15.887% to +30.671%, and
the host was visibly nonstationary. It is retained only as
provenance-incomplete exploratory data and is not evidence for a 5% speedup.

## Motivation and generated IR

redb 4.1.0 performs binary searches in leaf and branch pages, including
`LeafAccessor::position` and `BranchAccessor::child_for_key`. The benchmark's
keys are 24-byte byte slices, so hot monomorphizations repeatedly classify the
signed result of byte-slice comparison and dispatch on `Ordering`.

After Rust and LLVM's normal optimized pipeline, the focused redb probe retains
this shape:

```llvm
%cmp = call i8 @llvm.scmp.i8.i64(i64 %left, i64 %right)
switch i8 %cmp, label %invalid [
  i8 -1, label %less
  i8  0, label %equal
  i8  1, label %greater
]

invalid:
  unreachable
```

On x86-64, representative baseline code normalized the comparison with a
`test`, `sets`, `setg`, and `sub`, then compared the normalized result again.
The replacement lets instruction selection use the original flags directly: a
sign branch followed by an equality branch. It avoids materializing an
`Ordering` discriminant without changing which successor executes.

## Transformation and matcher boundary

The pass replaces the switch with this control flow:

```llvm
%aco.left = freeze i64 %left
%aco.right = freeze i64 %right
%aco.less = icmp slt i64 %aco.left, %aco.right
br i1 %aco.less, label %less, label %aco.scmp.nonless

aco.scmp.nonless:
%aco.equal = icmp eq i64 %aco.left, %aco.right
br i1 %aco.equal, label %equal, label %greater
```

The matcher is intentionally narrow. It requires all of the following:

- the condition is `llvm.scmp` returning `i8` from two `i64` operands;
- the comparison has exactly one use;
- the switch has exactly three cases, whose constants are exactly `-1`, `0`,
  and `1`;
- less, equal, greater, and default are distinct destinations; and
- the default block terminates in `unreachable`.

The pass freezes each operand once in the source block before either
comparison. This is semantically inert for ordinary defined values and
preserves correlation when an undef-producing SSA value is reused in the two
stages. It then removes the obsolete default predecessor, moves equal and
greater PHI predecessors to the new non-less block, leaves the less predecessor
on the source block, and reports no preserved analyses after a rewrite. Focused
negative fixtures retain an unsupported `i32` comparison and a noncanonical
two-case switch.

The LLVM regression asserts the complete route mapping, not just predicates:

- signed-less goes to `less`, otherwise to `aco.scmp.nonless`;
- equality from the non-less block goes to `equal`, otherwise to `greater`;
- both comparisons consume the same `aco.left` and `aco.right` freezes;
- less PHIs retain the source predecessor; and
- equal and greater PHIs use the non-less predecessor.

An additional fixture starts with an explicit undef left operand and asserts
that the emitted two-block CFG reuses one frozen value. Together these checks
catch both an equal/greater destination swap and uncorrelated repeated operand
uses even when the resulting IR remains verifier-valid.

## Alive2 safety proof

The main proof encodes the staged CFG result with nested selections: less
returns `-1`; otherwise equality returns `0` and the final route returns `1`.
The target freezes both operands once and feeds the same frozen values to its
`slt` and `eq` predicates. This models the route dependency that was absent
from the original flat classification proof.

The second positive obligation fixes the adversarial case to `left = undef`
and `right = INT64_MAX`. Its source freezes the undef before its single `scmp`
use; for a value used once this preserves the same observable choices while
making that one choice explicit to the standalone Alive language. Its target
freezes once and reuses the result. The matching negative candidate omits the
target freeze and is required to produce a semantic mismatch: it can observe
“not less” and later “not equal,” selecting greater even though the source can
only select less or equal.

Pinned Alive2 commit
`1d1bc4fe3135492a8c1166838c776530de479420` reports:

```text
Alive2 proved scmp-i64-switch-classification.opt
Alive2 proved scmp-i64-switch-undef-correlation.opt
Alive2 rejected 00-scmp-i64-switch-unfrozen.opt with a semantic mismatch
```

The fail-closed positive runner applies a 10-second SMT deadline, a 30-second
process deadline, and a 1 GiB memory limit. Diagnostics, counterexamples,
timeouts, ambiguous success output, and unsupported behavior all fail the
build. The negative runner checks every negative candidate independently and
requires a zero-status Alive2 invocation containing exactly one failed
transformation and one well-formed scalar counterexample. It retains stdout and
stderr separately and rejects warnings, unsupported behavior, timeouts,
crashes, extra diagnostics, malformed counterexamples, and accepted
transformations. This prevents a mismatch phrase from masking an invalid
solver outcome or one failing file from masking another candidate that Alive2
accidentally accepts.

The standalone proof represents the staged route with nested selections, while
CFG construction is implemented through LLVM's C++ API. A structural
consistency gate checks the intrinsic and widths, both freezes, both proved
target predicates, and the exact `IsLess -> Less/NonLess` and
`IsEqual -> Equal/Greater` calls. The focused `opt -verify-each` regression
then checks the emitted frozen operands, destinations, and PHIs. These
independent defenses keep the proof boundary explicit; the project does not
claim that Alive2 directly verified arbitrary C++ pass code.

A second candidate for narrowing Rust's widened `usize::midpoint` arithmetic
was explored. Alive2 timed out both the ordered-difference and carry-free
formulations, including a bounded 60-second diagnostic run. Under the
fail-closed policy, that candidate and its implementation were removed.

## redb integration coverage

Normal benchmark compilation does not enable optimizer tracing because that
would perturb build logs and cache behavior. The benchmark image therefore has
a separate integration gate:

1. copy `tests/redb-ir-probe`, which performs byte-slice insert, remove, and
   lookup operations against the pinned redb source;
2. compile it in release mode with the baseline and optimized compiler modes,
   tracing enabled, offline dependency resolution, and separate fresh temporary
   Cargo targets;
3. reject any `aco-keyhole` or `aco-three-way-compare` trace from baseline; and
4. require at least one `aco-three-way-compare: transformed` line from the
   optimized build.

A cached benchmark binary cannot satisfy either gate because both probe targets
are newly created for the image step. Injecting `RUSTFLAGS`, a Cargo compiler
wrapper, or another mechanism that schedules ACO in both variants causes the
baseline gate to fail. The rebuilt image reported baseline exclusion and two
optimized transforming trace lines.

## Historical diagnostic method and inference policy

The provenance-incomplete seven-pair diagnostic used:

- Rust commit `8bab26f4f68e0e26f0bb7960be334d5b520ea452` (Rust 1.97.1,
  LLVM 22.1.6);
- redb commit `6ed1f981ba4deab0b2adbdd7bccb46ec409b2191` (redb 4.1.0);
- identical custom compiler and sysroot artifacts for both variants, with only
  `-Zllvm-plugins` / `-Cpasses=aco-passes` disabled or enabled;
- seven paired rounds with baseline/optimized order alternated each round;
- `AuthenticAMD`, `AMD EPYC-Milan Processor`, CPUs 0-7;
- `clock_gettime(CLOCK_MONOTONIC)` for complete-process timing; and
- per-sub-benchmark native millisecond output retained in the raw log.

Its CPU metadata is complete, but its provenance manifest predates the Cargo
identity fix: `cargo_sha256` contains the rustup proxy hash `4acc9a…`, it lacks
`cargo_proxy_sha256`, and it does not retain the selected Cargo executable hash
`828980…`. Therefore the run cannot satisfy the exact-provenance claim made by
the current harness.

Duplicate read and range-read measurements within one invocation are averaged
to one paired value per round. Aggregate speedup is
`baseline_mean / optimized_mean - 1`. Paired intervals use the mean and sample
standard deviation of the seven within-round speedup ratios.

No sub-benchmark endpoint was predeclared before the historical experiments.
Consequently, selecting the best of twelve pointwise intervals would be
invalid. The summary now reports both:

- a descriptive pointwise interval using `t(0.975, 6) = 2.446912`; and
- a Bonferroni family-wise 95% interval across twelve endpoints using
  `t(1 - 0.05 / (2 * 12), 6) = 4.485768`.

The latter is the interval used for any statement selected after inspecting
the twelve results. No family-wise interval in any retained run excludes zero.
A future confirmatory experiment should predeclare single-thread random reads
as the primary endpoint because they exercise the affected B-tree search path,
then reserve the other categories for secondary analysis.

## Provenance-incomplete exploratory results

| redb endpoint | Baseline mean | Optimized mean | Aggregate speedup | Paired median | Pointwise 95% CI | Family-wise 95% CI |
|---|---:|---:|---:|---:|---:|---:|
| Random reads | 2100.357 ms | 1959.429 ms | **+7.192%** | +10.688% | -5.306%, +20.090% | -15.887%, +30.671% |
| Batch writes | 2066.857 ms | 1964.571 ms | +5.207% | +3.787% | +0.606%, +9.893% | -3.263%, +13.762% |
| Compaction | 5154.857 ms | 4901.571 ms | +5.167% | +2.246% | -3.708%, +15.249% | -11.606%, +23.147% |
| Bulk load | 18662.143 ms | 17901.857 ms | +4.247% | +6.321% | +0.430%, +8.201% | -2.808%, +11.439% |
| Removals | 12636.429 ms | 12200.000 ms | +3.577% | +3.940% | +0.553%, +6.639% | -1.982%, +9.175% |
| Complete process | 70.123 s | 68.131 s | +2.924% | +2.047% | +0.278%, +5.619% | not part of sub-benchmark family |

These figures are retained for historical inspection, not as performance
evidence. The run is not suitable for a causal performance claim. Pair-level
complete-process speedups range from -0.86% to +8.11%. In round three, baseline
random reads abruptly fell to 1559-1665 ms while adjacent samples were near
1900-2375 ms. In round six, optimized compaction fell to 4138 ms while adjacent
samples were near 5000-5332 ms. Similar broad improvements in bulk load,
writes, and removals are not specific to the comparison rewrite. The run is
retained as a record of the corrected multiple-comparison analysis, not because
its provenance or largest point estimate is trustworthy.

## Historical exploratory result

The quieter historical run observed random range reads at 1602.714 ms baseline
versus 1560.357 ms optimized, a +2.715% aggregate speedup. Its pointwise paired
95% interval is +0.804% to +4.644%, but its family-wise interval is **-0.795%
to +6.244%**. Thus the result is not statistically resolved after accounting
for selection across twelve endpoints.

That raw header predates CPU vendor/model capture. Although the executable
hashes match the seven-pair run, the historical measurement cannot be
fully attributed to a microarchitecture from its retained output, so it is
kept as exploratory history and is not the basis of a performance claim. The
older `scmp-switch-final` rerun is likewise retained only as a nonstationary
diagnostic.

## Build-input provenance hardening

`scripts/build-image.sh` now delegates every caller option to a deny-by-default
allowlist. Only resource limits, local cache controls, retries, pulling the
digest-pinned base, and log visibility are accepted. Environment injection,
build arguments, named build contexts, labels, source mounts, alternate build
files or stages, base-image replacement, platform changes, and every unknown
future option are rejected before Podman. This replaces a fragile list of known
override mechanisms with one explicit set of non-input controls. Regression
tests include all QA reproducers:

```text
build-image.sh proof-checker --env ALIVE2_COMMIT=qa-override
build-image.sh redb-benchmark --env 'RUSTFLAGS=-Zllvm-plugins=... -Cpasses=aco-passes'
build-image.sh proof-checker --build-context alive2-builder=container-image://...
```

Each exits with status 2 and reports that build inputs are pinned before any
image can be rebuilt under the protected tag.

Benchmark provenance resolves the Cargo invocation through `rustup which
cargo`. `cargo_sha256` covers the selected toolchain executable rather than the
rustup proxy, whose identity is retained separately as `cargo_proxy_sha256`.
The regression fixture models the official-image symlink layout and confirms a
Cargo-only replacement changes the former hash without changing the latter.

## Verification and artifacts

Completed checks:

- `make test`, including protected-input, exact-CFG, metadata, and statistics
  regressions;
- `make prove`, including the positive proofs and negative proof-gate controls;
- exact LLVM 22 plugin compilation and `opt -verify-each` pass regression;
- custom Rust toolchain image smoke and compiler-cache regressions;
- all 37 redb library tests in baseline and optimized modes;
- separate fresh redb probe builds proving baseline exclusion and optimized matching;
- redb benchmark image smoke checks; and
- one-round `make benchmark` with the final provenance fields plus a retained,
  explicitly provenance-incomplete seven-pair diagnostic.

Relevant files:

- pass: `optimizer/OptimizerPlugin.cpp`;
- proofs: `optimizer/proofs/scmp-i64-switch-classification.opt` and
  `scmp-i64-switch-undef-correlation.opt`;
- required negative proof: `tests/alive2/00-scmp-i64-switch-unfrozen.opt`;
- pass fixtures: `optimizer/tests/optimizer.ll` and `optimizer/test.sh`;
- proof/implementation consistency: `tests/optimizer-proof-consistency.sh`;
- redb coverage probe: `tests/redb-ir-probe/`;
- variant trace verifier: `scripts/verify-redb-variant-traces.sh`;
- build option allowlist: `scripts/validate-build-options.sh`;
- closed-bundle provenance: `scripts/write-benchmark-provenance.sh`;
- corrected statistics: `scripts/summarize-redb-subbenchmarks.sh`;
- provenance-incomplete diagnostic:
  `results/scmp-switch-provenance-incomplete/README.md`, `raw.log`,
  `total-times.tsv`, and `subbench-summary.tsv`; and
- historical exploratory data: `results/scmp-switch/` and
  `results/scmp-switch-final/`.

To reproduce the proof and integration gates:

```sh
make test
make prove
make toolchain-image
make benchmark-image
make benchmark
```

For a confirmatory performance run, predeclare the random-read endpoint, use an
otherwise idle host, retain at least seven paired rounds, and reject the run if
system load or within-run timing shows a regime change.
