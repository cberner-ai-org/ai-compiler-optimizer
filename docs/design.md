# Design

## Status

This project is experimental. Its scaffold builds an editable, pinned stage-1 Rust compiler, loads
a no-op LLVM keyhole pass into that compiler, and uses the complete path to compile a pinned redb
benchmark. The pass establishes optimizer plumbing but does not yet transform IR. The project does
not yet contain an LLM integration or a solver integration.

## Objective

The long-term goal is to discover LLVM peephole optimizations that make Rust programs faster while
retaining a machine-checked equivalence argument for every accepted rewrite. An LLM will propose
small optimization passes, a coding agent will implement and test them, and a solver framework will
prove that each transformation preserves the behavior of the source program under its stated
preconditions.

The initial workload is [redb](https://github.com/cberner/redb). Work in this repository should
focus on optimizations that measurably improve redb's benchmark performance. Optimizations may be
general-purpose, but redb provides the motivating code, measurement harness, and first acceptance
test.

## Principles

1. **Proof is required.** An optimization is not eligible for integration unless the solver proves
   its equivalence. A timeout, unknown result, unsupported operation, or incomplete model is a
   rejection, not partial evidence.
2. **Keep transformations local.** Small, explicit peephole rewrites make proof obligations,
   implementation review, and regression diagnosis tractable.
3. **Benchmark the complete compiler path.** Solver success establishes safety; only end-to-end redb
   measurements establish usefulness.
4. **Preserve artifacts.** Candidate definitions, preconditions, solver inputs and results, generated
   code, compiler revisions, redb revisions, and benchmark samples must be attributable to one
   experiment.
5. **Treat tests as defense in depth.** Compiler tests and redb tests catch integration errors, but
   they do not replace the equivalence proof.

## Proposed architecture

The system is expected to grow into the following components:

- **Experiment orchestrator:** selects hot code patterns, asks the LLM for candidates, invokes the
  coding agent, schedules proofs and tests, and records results.
- **Candidate representation:** describes the input pattern, replacement, type constraints,
  preconditions, and LLVM semantic features used by a rewrite.
- **Solver adapter:** translates a candidate into an equivalence query and returns a proof,
  counterexample, or rejection. The model must account for the LLVM semantics relevant to the
  candidate, including poison, undef, overflow flags, memory behavior, and undefined behavior.
- **Pass workspace:** `optimizer` currently contains the no-op LLVM 22 plugin insertion point. It
  will contain generated pass implementations and focused positive and negative tests. Generated
  changes remain ordinary reviewable source code.
- **Compiler builder:** builds the pinned stage-1 rustc/LLVM toolchain and will include only accepted
  passes as optimizer work is added.
- **Benchmark harness:** compiles a fixed redb revision with baseline and experimental compilers,
  executes repeated benchmark samples in controlled environments, and compares their distributions.
- **Artifact store:** records enough provenance to reproduce both a proof and a performance result.

## Optimization lifecycle

Each candidate moves through a fail-closed pipeline:

1. Identify a frequent or expensive LLVM IR pattern produced while compiling redb.
2. Ask the LLM to propose a local replacement and explicit applicability conditions.
3. Have a coding agent implement the candidate representation, pass, and focused tests.
4. Generate the solver query from the same representation used by the pass.
5. Reject the candidate if the solver returns a counterexample, timeout, unknown result, or uses an
   unsupported semantic feature.
6. Build the compiler and run compiler regression tests for candidates with successful proofs.
7. Compile redb with the accepted pass and compare repeated results against the baseline compiler.
8. Retain the pass only when the speedup is reproducible and does not introduce unacceptable
   compile-time or code-size regressions.

Generating the pass and proof obligation from one declarative candidate representation is preferred:
it reduces the risk that the proved rewrite and implemented rewrite diverge. If independent forms are
temporarily necessary, structural consistency checks must be part of acceptance.

## Safety model

For every input admitted by a candidate's matching conditions, the replacement must refine the
behavior of the original LLVM fragment according to the semantics modeled by the solver framework.
The proof boundary and assumptions must be explicit and versioned.

Particular care is required for:

- integer overflow and `nsw`, `nuw`, and `exact` flags;
- poison and undef propagation;
- pointer provenance, aliasing, alignment, and in-bounds assumptions;
- memory effects, atomics, concurrency, and volatile operations;
- floating-point modes and fast-math flags;
- target-specific instructions and data layouts; and
- differences between the solver's LLVM model and the LLVM revision embedded in rustc.

The initial implementation should prefer pure integer and bitwise rewrites with no memory effects.
Expanding the supported semantic surface should require dedicated model tests and documented review.

Proof results are necessary but not sufficient. The integrated pass must also pass focused compiler
tests, the relevant Rust test suites, redb tests, and end-to-end benchmarks. These checks defend
against pass plumbing mistakes, mismatched tool versions, and errors outside the solver's proof
boundary.

## redb benchmark baseline

The current workflow pins Rust and redb as submodules and builds an editable stage-1 compiler plus
the no-op keyhole plugin in a Podman image. `make benchmark-image` runs redb's library tests,
compiles `redb_benchmark` with the plugin-aware compiler wrapper, and copies Cargo's reported
executable into the final image. `make benchmark` runs the five-million-item load, read, removal,
and compaction workload.

The container base is selected by an immutable registry digest, and every apt installation resolves
against a dated Debian snapshot. Both identities are centralized in `config/versions.env`, enforced
by scaffold checks, and copied into the resulting image labels. Changing either is a benchmark-input
change, so baseline and experimental artifacts must be rebuilt from the same new environment.

Compiler and Cargo build directories are persistent caches, not provenance authorities. Compiler
source and artifact identities participate in Cargo's fingerprint, while executable selection comes
from the current Cargo event stream. The redb worktree must be clean and its dependency lockfile is
tracked in this repository. Regression probes cover compiler-cache invalidation and stale artifact
selection.

This baseline establishes reproducible inputs and compiler plumbing, but it does not yet provide a
statistically rigorous comparison harness. Before optimization results are claimed, the harness must
capture machine characteristics, perform warmups and repeated randomized baseline/experimental runs,
and report uncertainty rather than only a single elapsed time.

## Optimizer integration scaffold

rustc's existing `-Zllvm-plugins` hook loads `libaco_keyhole_pass.so`, and `-Cpasses=aco-keyhole`
appends its function pass to the per-module LLVM pipeline. The pass currently changes no IR and
preserves all analyses. The container smoke test enables trace output to prove that the scheduled
pass visits generated functions; normal builds do not trace.

The plugin is compiled against the exact CI LLVM used by the stage-1 compiler, so no second LLVM or
large `llvm-project` checkout is required. The built pass binary participates in the compiler
identity used for Cargo cache invalidation, while its source remains attributable through the
repository revision. Later work must add only solver-accepted rewrites to this insertion point and
compare pinned baseline and experimental identities. Proof and benchmark artifacts must identify
the exact compiler, pass set, redb revision, dependency graph, and measurement environment.

## Milestones

1. **Baseline scaffold (current):** pinned editable rustc, pinned redb and dependencies, a loadable
   no-op optimizer insertion point, persistent compilation caches with explicit provenance, and a
   containerized benchmark.
2. **Measurement harness:** pinned inputs, repeated A/B runs, machine metadata, and structured result
   capture.
3. **Proof prototype:** declarative candidates and a solver adapter for a narrow integer-only subset.
4. **Pass prototype:** replace the integrated no-op with one generated and tested solver-proven LLVM
   peephole pass.
5. **Optimizer integration:** build rustc with accepted passes and use it for the redb A/B benchmark.
6. **Automated search:** let the LLM and coding agent propose, disprove or prove, implement, and
   benchmark candidates with auditable artifacts and human review gates.
