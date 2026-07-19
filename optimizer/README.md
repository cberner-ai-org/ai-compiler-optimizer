# ACO optimizer plugin

`OptimizerPlugin.cpp` defines the aggregate `aco-passes` LLVM new-pass-manager pipeline. Its
`ThreeWayCompareSwitchPass` lowers a canonical signed `llvm.scmp.i8.i64` switch to staged less-than
and equality branches. It freezes each reused operand once, repairs successor PHIs, and applies only
when the default destination is unreachable. The trailing keyhole pass remains a no-op pipeline
smoke check. Add future solver-proven passes to `addAcoPasses` in their intended pipeline order.

The container build compiles the plugin with the `llvm-config --cxxflags` from rustc's matching CI
LLVM. `rustc-with-aco-passes` loads it with `-Zllvm-plugins` and appends the aggregate pipeline to
rustc's per-module pipeline with `-Cpasses=aco-passes`. This keeps pass-only edits independent of
the much larger stage-1 compiler build.

Set `ACO_OPTIMIZER_TRACE=1` for integration traces. The comparison pass reports transformed
switches, while the keyhole pass reports every defined function it visits. Production benchmark
builds leave tracing unset; the benchmark image enables it only for fresh baseline and optimized
probe builds that verify the A/B boundary.

Do not add another transforming rewrite until its proof obligation and focused positive and
negative tests are available. A pass must return analysis preservation that reflects every change
it makes; the comparison pass preserves nothing after a rewrite, while the no-op keyhole pass
preserves every analysis.

`proofs/` contains one declarative Alive2 refinement obligation per candidate. Run `make prove` to
build the pinned solver and check every obligation with fail-closed timeout, resource, diagnostic,
and result handling. `scaffold-identity.opt` only exercises that gate. The two `scmp` obligations
prove the staged classification and explicit undef-correlation cases; independently checked
negative obligations demonstrate that inequivalent and unfrozen variants are rejected. The focused
LLVM regression and `tests/optimizer-proof-consistency.sh` bind the C++ matcher, exact CFG mapping,
frozen operands, and PHI repair to the proved candidate boundary.
