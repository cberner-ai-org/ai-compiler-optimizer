# Design

## Status

This project is experimental. Its first milestone is a reproducible baseline benchmark; it does not
yet contain a custom compiler, optimization passes, an LLM integration, or a solver integration.

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
- **Pass workspace:** contains generated LLVM pass implementations and focused positive and negative
  tests. Generated changes remain ordinary reviewable source code.
- **Compiler builder:** eventually builds a custom rustc/LLVM toolchain that loads or includes only
  accepted passes.
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

## redb benchmark scaffold

The current `just bench_redb` target builds a container based on the official Rust 1.90 Bookworm
image. At runtime the container creates a fresh redb checkout, resolves `REDB_REVISION` (defaulting
to `master`), prints the tested commit, and runs:

```console
cargo bench -p redb-bench --bench redb_benchmark
```

The named `ai-compiler-optimizer-redb-cache` Podman volume stores Cargo's registry, Git database, and
target directory across invocations. The source checkout itself is ephemeral, preventing stale or
modified source from contaminating a run. CI invokes the same `just` target used locally.

This first scaffold establishes that upstream redb builds and runs in the benchmark environment. It
does not attempt to produce statistically rigorous comparisons. Before optimization results are
claimed, the harness must pin the redb and compiler commits, isolate benchmark data from build caches,
capture machine characteristics, perform warmups and repeated randomized baseline/experimental runs,
and report uncertainty rather than only a single elapsed time.

## Planned custom compiler integration

A later milestone will build a rustc binary whose LLVM pipeline includes accepted custom passes. The
container will then compile the same redb revision twice: once with a pinned baseline rustc and once
with the experimental rustc. That work is intentionally deferred. The current benchmark uses the
unmodified Rust compiler supplied by the container image.

## Milestones

1. **Baseline scaffold (current):** containerized redb checkout, persistent compilation cache, one
   `just` command, and CI execution.
2. **Measurement harness:** pinned inputs, repeated A/B runs, machine metadata, and structured result
   capture.
3. **Proof prototype:** declarative candidates and a solver adapter for a narrow integer-only subset.
4. **Pass prototype:** generate and test one solver-proven LLVM peephole pass independently of rustc.
5. **Custom rustc:** build rustc with accepted passes and use it for the redb A/B benchmark.
6. **Automated search:** let the LLM and coding agent propose, disprove or prove, implement, and
   benchmark candidates with auditable artifacts and human review gates.
