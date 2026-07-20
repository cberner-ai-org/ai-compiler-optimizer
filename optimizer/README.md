# ACO optimizer plugin

`OptimizerPlugin.cpp` defines the default `aco-passes` LLVM new-pass-manager pipeline. It runs only
`ThreeWayCompareSwitchPass`, which lowers a canonical signed
`llvm.scmp.i8.i64` switch to staged less-than and equality branches. It freezes each reused operand
once, repairs successor PHIs, and applies only when the default destination is unreachable. Each
pass preserves every analysis only when it makes no change. Add future solver-proven passes to
`addAcoPipeline` only after performance evidence supports default enablement.

`KeyholePass` expands eligible `memcmp` calls, specializes the slice-ordering use chain, and narrows
ordered binary-search midpoints. Those rewrites remain proved and available for explicit
experiments, but are disabled by default because the latest seven-pair redb ablation found negative
marginal whole-process point estimates and a robust full-pipeline nosync-write regression.

The same plugin exposes attribution pipelines that can be selected independently:

- `aco-midpoint-only`: ordered midpoint narrowing only;
- `aco-slice-comparison-only`: slice ordering plus eligible general `memcmp` fast paths;
- `aco-key-comparisons`: both keyhole modes, without signed switch lowering; and
- `aco-all-passes`: both keyhole modes followed by signed switch lowering.

`aco-passes` is the performance-gated default and enables signed switch lowering only. The explicit
`aco-all-passes` pipeline preserves the former composition. It schedules the keyhole pass first
because the slice matcher needs the original `llvm.scmp` use chain before the comparison pass lowers
it.

The container build compiles the plugin with the `llvm-config --cxxflags` from rustc's matching CI
LLVM. `rustc-with-aco-passes` loads it with `-Zllvm-plugins` and appends the default pipeline to
rustc's per-module pipeline with `-Cpasses=aco-passes`. This keeps pass-only edits independent of
the much larger stage-1 compiler build.

Set `ACO_OPTIMIZER_TRACE=1` for integration traces. The comparison pass reports transformed
switches, while the keyhole pass reports every changed function with per-rewrite counts. Production
benchmark builds leave tracing unset; the benchmark image enables it only for fresh baseline and
optimized probe builds that verify the A/B boundary.

Do not add another transforming rewrite until its proof obligation and focused positive and
negative tests are available. A pass must return analysis preservation that reflects every change
it makes.

`proofs/` contains one declarative or exact LLVM Alive2 refinement obligation per proof unit. Run
`make prove` to build the pinned solver and check every obligation with fail-closed timeout,
resource, diagnostic, and result handling. `scaffold-identity.opt` only exercises that gate. The two
`scmp` obligations
prove the staged classification and explicit undef-correlation cases; independently checked
negative obligations demonstrate that inequivalent and unfrozen variants are rejected. The focused
LLVM regression and `tests/optimizer-proof-consistency.sh` bind the C++ matcher, exact CFG mapping,
frozen operands, and PHI repair to the proved candidate boundary.

The slice-ordering rewrite is compositional: the general memcmp expansion is proved first, then
three mutually exclusive and exhaustive path obligations prove its specialized use. `test.sh`
applies the real C++ pass twice to positive and near-miss LLVM fixtures, checks exact transform
counts, and verifies idempotence. `isProvenMemcmpCall` owns the memcmp ABI/type proof boundary,
while `hasUnsupportedCallControlContract` owns the control-placement boundary for both calls
relocated by the slice rewrite. It admits only default-C calls without operand bundles or control
contracts such as `convergent`, `musttail`, `notail`, `noreturn`, `returns_twice`, or
`noduplicate`. An ordinary `tail` hint is not a control contract and is cleared from either
relocated call. The memcmp matcher requires every explicit call-site or declaration memory contract
to describe read-only argument memory. An absent memory attribute leaves the recognized libc
semantics in force; explicit write or non-argument effects are rejected. It admits either no
call-site return/parameter contracts or Rust's exact shape with `nonnull` on both pointer operands;
a separate Alive2 obligation covers each shape.
Every other call-site contract is rejected, and the declaration may retain only its capture
contract. The proved memcmp domain is little-endian, 64-bit, address-space-zero, with an `i64`
length.

Because specialization moves the comparison chain behind the equal-byte branch, the rewrite sinks
unrelated instructions between `memcmp` and `llvm.scmp` to the shared continuation. Eligibility
requires every sunk operand to dominate the new branch and rejects interleaved calls with
control-placement contracts such as `convergent`. Adversarial fixtures verify that an ordinary
interleaved side-effecting call remains unconditional and executes exactly once, run verifier-valid
`musttail`, `notail`, and convergent ordering calls through the public plugin with `-verify-each`,
and verify that an ordinary ordering `tail` hint is safely cleared. Additional verifier-backed
fixtures reject unproved argument contracts and call/declaration memory effects outside read-only
argument memory.
