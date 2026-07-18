# Design

## Status

This project is experimental. Its scaffold builds an editable, pinned stage-1 Rust compiler, loads
a no-op LLVM optimization pipeline into that compiler, proves declarative rewrite obligations with
a pinned Alive2 image, and uses the complete compiler path to compile paired pinned redb benchmarks
with the pipeline disabled and enabled. The pass establishes optimizer and A/B measurement plumbing
but does not yet transform IR. The project does not yet contain an LLM integration or a transforming
solver-accepted candidate.

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
- **Solver adapter:** `scripts/verify-alive2-proofs.sh` submits one declarative candidate at a time to
  pinned Alive2 and accepts only one unqualified refinement result. A counterexample, diagnostic,
  timeout, resource failure, unsupported feature, parse or type error, or ambiguous output is a
  rejection. The model must account for the LLVM semantics relevant to the candidate, including
  poison, undef, overflow flags, memory behavior, and undefined behavior.
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

## Alive2 proof boundary

[Alive2](https://github.com/AliveToolkit/alive2) is an SMT-backed LLVM refinement checker. Its
[PLDI 2021 paper](https://doi.org/10.1145/3453483.3454030) defines correctness as the target exposing
no behavior that the source lacks, which handles LLVM undefined behavior more accurately than plain
input/output equality. The paper also makes the bounded nature of translation validation explicit.
[LLM-Vectorizer](https://arxiv.org/abs/2406.04693) demonstrates the relevant LLM architecture:
generated optimizations are candidates until Alive2 proves them, while unsupported cases and
resource limits remain inconclusive rather than becoming accepted transformations.

This prototype builds Alive2's declarative `alive` verifier without a second LLVM checkout. Each
tracked `.opt` file contains exactly one local source-to-target refinement obligation. Poison and
undef inputs remain enabled. Both SMT and process deadlines are enforced, solver memory is bounded,
and any stderr output is a rejection. The proof-checker image runs a positive identity obligation and
a known-inequivalent negative regression during its build, then can rerun the embedded accepted
obligations without network access.

The current boundary proves the candidate specification, not arbitrary C++ pass code. Before the
keyhole pass performs a rewrite, the implementation and proof must come from one declarative source
or gain a structural consistency test. Direct pass-output translation validation with `alive-tv`
would require a separate LLVM build with RTTI and exceptions; it is intentionally deferred until the
candidate representation and generated-pass seam exist.

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

## redb benchmark comparison

The current workflow pins Rust and redb as submodules and builds an editable stage-1 compiler plus
the no-op optimizer plugin in a Podman image. `make benchmark-image` runs redb's library tests and
compiles `redb_benchmark` twice: baseline invokes the stage-1 compiler directly, while optimized
invokes that same compiler with the custom pass pipeline loaded and scheduled. Cargo's event stream
selects each resulting executable for the final runtime image. `make benchmark` runs both through
the five-million-item load, read, removal, and compaction workload.

The container base is selected by an immutable registry digest, and every apt installation resolves
against a dated Debian snapshot. Both identities are centralized in `config/versions.env`, enforced
by scaffold checks, and copied into the resulting image labels. Changing either is a benchmark-input
change, so baseline and experimental artifacts must be rebuilt from the same new environment.

Compiler and Cargo build directories are persistent caches, not provenance authorities. Mutable
rustc and redb target caches are namespaced by an enforced ID derived from the base-image digest and
Debian snapshot. After the toolchain stage is complete, it owns and emits one compiler-artifact
manifest and ID covering the source build ID, rustc, rustc driver, dynamically loaded LLVM library,
and complete sysroot. Cache selection and benchmark provenance consume this same precomputed ID
rather than independently enumerating compiler inputs. Within the redb cache, baseline and optimized
artifacts use directories selected from that core ID plus artifacts owned by each mode. A plugin-only
change invalidates optimized artifacts but leaves baseline artifacts fresh. Identity-only compiler
flags are deliberately avoided because they can change symbol names or binary layout and become an
A/B confounder. The checksum-verified Cargo registry cache may be shared across environments.
Executable selection comes from each current Cargo event stream. The redb worktree must be clean and
its dependency lockfile is tracked in this repository. Regression probes cover variant isolation,
compiler-cache invalidation, and stale artifact selection.

Artifact identities follow one lifecycle rule: the stage that owns a bundle emits its identity only
after the bundle is complete, and consumers reuse that identity without rebuilding a partial view.
The toolchain stage owns compiler code-generation artifacts. The benchmark-builder stage owns the
runtime experiment bundle, so it assembles both benchmarks, the monotonic clock helper, and the
comparison runner before generating benchmark provenance. The final runtime stage copies this
closed bundle and its manifest together.

The runtime harness labels each variant's native benchmark output, records total wall time, reports
binary hashes, effective CPU affinity, and basic machine characteristics, and alternates execution
order across repeated rounds. Elapsed samples use `clock_gettime(CLOCK_MONOTONIC)` through a hashed
repository-owned helper, and non-positive deltas fail the experiment. A caller can retain the raw
tab-separated samples through a mounted result path. The runtime image also embeds and reports a
manifest containing the shared compiler artifact ID and component hashes, plugin and wrapper hashes,
pinned source and environment revisions, dependency-lock identity, both output hashes, and the
comparison runner hash. The runner verifies itself and the measured artifacts before collecting a
sample. A caller can therefore attribute a sample without retaining the discarded build stages. The
default single round is only an integration check. Before optimization results are claimed,
experiments must use repeated runs on a controlled idle host and report the sample distribution and
uncertainty, not only the harness's mean wall-time ratio.

## Optimizer integration scaffold

rustc's existing `-Zllvm-plugins` hook loads `libaco_optimizer.so`, and `-Cpasses=aco-passes`
appends the aggregate ACO pipeline to the per-module LLVM pipeline. `addAcoPasses` is the explicit
ordering point for accepted custom passes. Its current keyhole pass changes no IR and preserves all
analyses. The container smoke test enables trace output to prove that the scheduled pass visits
generated functions; normal builds do not trace.

The plugin is compiled against the exact CI LLVM used by the stage-1 compiler, so no second LLVM or
large `llvm-project` checkout is required. The built pass binary participates in the compiler
identity used for Cargo cache invalidation, while its source remains attributable through the
repository revision. Alive2 is independently pinned because proof semantics are an experiment input.
Later work must add only solver-accepted rewrites to this insertion point. The benchmark baseline
must continue to bypass the plugin entirely while the optimized variant schedules the accepted pass
set. Proof and benchmark artifacts must identify the exact compiler, pass set, redb revision,
dependency graph, and measurement environment.

## Milestones

1. **Baseline scaffold (complete):** pinned editable rustc, pinned redb and dependencies, a loadable
   no-op optimizer insertion point, a fail-closed pinned Alive2 proof gate, and persistent
   compilation caches with explicit provenance.
2. **Measurement harness (scaffold complete):** paired pass-disabled/pass-enabled artifacts,
   alternating repeated A/B runs, basic machine metadata, and structured raw wall-time capture;
   distribution and uncertainty reporting remains experiment-level work.
3. **Proof prototype (scaffold complete):** declarative candidates and a solver adapter for a narrow
   integer-only subset; candidate-to-pass generation or structural consistency remains.
4. **Pass prototype:** replace the integrated no-op with one generated and tested solver-proven LLVM
   peephole pass.
5. **Optimizer integration:** build rustc with accepted passes and use it for the redb A/B benchmark.
6. **Automated search:** let the LLM and coding agent propose, disprove or prove, implement, and
   benchmark candidates with auditable artifacts and human review gates.
