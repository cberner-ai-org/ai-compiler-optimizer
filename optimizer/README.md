# ACO optimizer plugin

`OptimizerPlugin.cpp` defines the aggregate `aco-passes` LLVM new-pass-manager pipeline. The current
keyhole pass visits every defined function, changes no IR, and preserves every analysis. Add future
solver-proven passes to `addAcoPasses` in their intended pipeline order.

The container build compiles the plugin with the `llvm-config --cxxflags` from rustc's matching CI
LLVM. `rustc-with-aco-passes` loads it with `-Zllvm-plugins` and appends the aggregate pipeline to
rustc's per-module pipeline with `-Cpasses=aco-passes`. This keeps pass-only edits independent of
the much larger stage-1 compiler build.

Set `ACO_OPTIMIZER_TRACE=1` for an integration check that prints one line for every function
visited. Production benchmark builds leave tracing unset.

Do not add a transforming rewrite here until its proof obligation and focused positive and negative
tests are available. A pass must return analysis preservation that reflects every change it makes;
`PreservedAnalyses::all()` is valid only while the pipeline changes no IR.

`proofs/` contains one declarative Alive2 refinement obligation per candidate. Run `make prove` to
build the pinned solver and check every obligation with fail-closed timeout, resource, diagnostic,
and result handling. `scaffold-identity.opt` only exercises that gate; it does not authorize a pass
rewrite. A transforming implementation must be generated from the proved candidate or have a
structural test demonstrating that the C++ matcher and replacement are the same obligation.
