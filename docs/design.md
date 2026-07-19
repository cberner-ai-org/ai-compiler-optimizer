# Design

## Status

This project is experimental. It builds an editable, pinned stage-1 Rust compiler, loads a custom
LLVM optimization pipeline into that compiler, proves declarative and exact LLVM refinements with a
pinned Alive2 image, and uses the complete compiler path to compile paired pinned redb benchmarks
with the pipeline disabled and enabled. Accepted passes lower canonical signed three-way comparison
switches, specialize byte-slice comparisons, and narrow ordered binary-search midpoints. The project
does not yet contain an LLM integration or automated candidate generation.

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
- **Pass workspace:** `optimizer` contains the LLVM 22 plugin insertion point, the accepted signed
  three-way comparison and keyhole passes, focused positive and negative IR fixtures, idempotence
  regressions, and exact Alive2 obligations. Generated changes remain ordinary reviewable source
  code.
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

This prototype builds Alive2's `alive` and `alive-tv` verifiers against the exact LLVM 22 archive
used by the pinned stage-1 rustc. A small compatibility patch is tracked because the pinned Alive2
revision predates LLVM 22 API changes. Each `.opt` or `.srctgt.ll` file contains exactly one
source-to-target refinement. Poison and undef remain enabled. Both SMT and process deadlines are
enforced, solver memory is bounded, and proof output is treated as a protocol: stderr must be empty,
stdout must contain exactly one unqualified success result, and any Alive2 warning, error, note, or
unsupported-operation record on stdout is a rejection. Exact-LLVM obligations also use
`-fail-src-ub`, so a vacuous always-undefined source is an error rather than an acceptable warning.
Declarative obligations use `-root-only`, so helper names do not become accidental proof
requirements. The proof-checker image runs every accepted obligation and every negative regression
independently during its build, then can rerun the embedded obligations without network access.
Negative controls require exactly one well-formed semantic counterexample without diagnostics.

The proof boundary is the exact LLVM fragment and matcher preconditions, not arbitrary C++ pass
code. Structural consistency tests bind the signed-comparison matcher and CFG repair to its
declarative obligations. Focused tests apply the keyhole pass to positive and near-miss fixtures and
run it twice to check idempotence. The accepted slice specialization is proved compositionally: one
obligation validates the complete `memcmp` first-byte expansion, then three obligations partition
the follow-on ordering fold into zero length, equal first bytes, and unequal first bytes. Those
conditions are mutually exclusive and exhaustive after the emitted freezes. This keeps each solver
query tractable while covering every target path. One C++ predicate owns the corresponding memcmp
ABI/type proof domain: only address-space-zero 64-bit pointers, an `i64` length, and a little-endian
64-bit data layout are eligible. A second centralized predicate owns the lifecycle rule for every
call the rewrite relocates across new control flow. Both calls must use the default C calling
convention and reject operand bundles, convergence, mandatory or prohibited tail placement, and
other control-sensitive function attributes. An ordinary `tail` marker is only a discardable hint;
the rewrite clears it from either relocated call. Structural consistency checks and verifier-backed
adversarial fixtures bind these fail-closed checks to the tracked obligation.

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

Memory-sensitive rewrites require an exact libc model, explicit pointer and length conditions,
dedicated model tests, and documented review. The first-byte optimization uses Alive2's `memcmp`
model and emits loads only after proving the frozen length nonzero.

Proof results are necessary but not sufficient. The integrated pass must also pass focused compiler
tests, the relevant Rust test suites, redb tests, and end-to-end benchmarks. These checks defend
against pass plumbing mistakes, mismatched tool versions, and errors outside the solver's proof
boundary.

## redb benchmark comparison

The current workflow pins Rust and redb as submodules and builds an editable stage-1 compiler plus
the optimizer plugin in a Podman image. `make benchmark-image` runs redb's library tests and
compiles `redb_benchmark` in five modes: baseline invokes the stage-1 compiler directly; midpoint,
slice-comparison, key-comparisons, and optimized invoke that same compiler with independently
selected custom pipelines. Cargo's event stream selects each resulting executable for the final
runtime image. A provenance-bound runtime selector compares any one candidate with the shared
baseline through the five-million-item load, read, removal, and compaction workload.

The container base is selected by an immutable registry digest, and every apt installation resolves
against a dated Debian snapshot. Both identities are centralized in `config/versions.env`, enforced
by scaffold checks, and copied into the resulting image labels. Changing either is a benchmark-input
change, so baseline and experimental artifacts must be rebuilt from the same new environment.

Build inputs are closed and owned by the repository. `scripts/build-image.sh` delegates to a
deny-by-default option allowlist rather than trying to enumerate every dangerous Podman feature.
Only resource limits, local cache controls, retries, pulling the digest-pinned base, and log
visibility pass through. Environment injection, build arguments, named build contexts, labels,
source mounts, alternate build files or stages, base-image replacement, and platform changes are
rejected. This prevents a new Podman input channel from silently bypassing cache identity and
provenance; adding another passthrough category requires an explicit design review.

Compiler and non-measured redb test/probe build directories are persistent caches, not provenance
authorities. Mutable rustc and redb test/probe target caches are namespaced by an enforced ID derived
from the base-image digest and Debian snapshot. Timed benchmark builds are different: every mode
starts with an absent target directory under `/tmp`, installs the executable selected by that Cargo
event stream, and removes the directory before committing the layer. Thus a layer rebuild cannot
turn a reported clean compile into a persistent target-cache hit. After the toolchain stage is
complete, it owns and emits one compiler-artifact
manifest and ID covering the source build ID, rustc, rustc driver, dynamically loaded LLVM library,
and complete sysroot. Cache selection and benchmark provenance consume this same precomputed ID
rather than independently enumerating compiler inputs. Within the reusable redb test/probe cache,
baseline and each candidate use directories selected from that core ID plus artifacts owned by each
mode. A plugin-only change invalidates candidate test/probe artifacts but leaves baseline artifacts
fresh. Identity-only compiler flags are deliberately avoided because they can change symbol names or
binary layout and become an A/B confounder. The checksum-verified Cargo registry cache may be shared
across environments, including for clean-target timed builds.
Executable selection comes from each current Cargo event stream. The redb worktree must be clean and
its dependency lockfile is tracked in this repository. Regression probes cover variant isolation,
compiler-cache invalidation, and stale artifact selection.

Artifact identities follow one lifecycle rule: the stage that owns a bundle emits its identity only
after the bundle is complete, and consumers reuse that identity without rebuilding a partial view.
The toolchain stage owns compiler code-generation artifacts. The benchmark-builder stage owns the
runtime experiment bundle, so it assembles the baseline and all candidate benchmarks, the monotonic
clock helper, and the comparison runner before generating per-candidate benchmark provenance. The
final runtime stage copies this closed bundle and its manifests together.

The runtime harness labels each variant's native benchmark output, records total wall time, reports
binary hashes, effective CPU affinity, CPU vendor and model, and basic machine
characteristics, and alternates execution order across repeated rounds. Elapsed samples use
`clock_gettime(CLOCK_MONOTONIC)` through a hashed repository-owned helper, and non-positive deltas
fail the experiment. A caller can retain raw overall and phase-level tab-separated samples through
mounted result paths. The runtime image also embeds and reports a
manifest containing the shared compiler artifact ID and component hashes, plugin and wrapper hashes,
pinned source and environment revisions, the rustup-selected Cargo executable and dispatch-proxy
hashes, dependency-lock identity, the selected output hashes, and the comparison runner hash. The
runner verifies itself and the measured artifacts before collecting a sample. A caller can therefore
attribute a sample without retaining the discarded build stages. The
default single round is only an integration check. Before optimization results are claimed,
experiments must use repeated runs on a controlled idle host and report the sample distribution and
uncertainty, not only the harness's mean wall-time ratio.

## Optimizer integration scaffold

rustc's existing `-Zllvm-plugins` hook loads `libaco_optimizer.so`, and `-Cpasses=aco-passes`
appends the aggregate ACO pipeline to the per-module LLVM pipeline. The plugin also exposes
`aco-midpoint-only`, `aco-slice-comparison-only`, and `aco-key-comparisons` for attribution.
`addAcoPipeline` is the explicit ordering point for accepted custom passes. The aggregate runs the
keyhole pass before the signed three-way comparison pass so the slice matcher can consume its exact
`llvm.scmp` use chain before that intrinsic is lowered. Each transforms only exact accepted patterns
and invalidates analyses only when it changes IR. The toolchain smoke enables trace output to prove
that the pipeline is scheduled. A
separate benchmark-image gate compiles a redb byte-slice probe from separate fresh baseline and
optimized Cargo targets. The baseline must emit no ACO trace and the optimized build must emit a
transforming trace. This proves both halves of the A/B boundary while normal benchmark builds remain
untraced.

The comparison pass freezes each `llvm.scmp` operand once before the staged less-than/equality
branches. This preserves the single-use correlation of undef-capable SSA values when the replacement
reuses those values in two basic blocks. Alive2 proves both the general staged route and an explicit
`undef` versus `INT64_MAX` obligation; a negative gate independently requires the corresponding
unfrozen candidate to fail with exactly one clean semantic counterexample. The negative adapter
retains Alive2's process status and separate output streams; warnings, unsupported behavior,
timeouts, crashes, additional diagnostics, and malformed counterexamples all fail closed.

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
   optimizer insertion point, a fail-closed pinned Alive2 proof gate, and persistent
   compilation caches with explicit provenance.
2. **Measurement harness (scaffold complete):** paired pass-disabled/pass-enabled artifacts,
   alternating repeated A/B runs, CPU microarchitecture metadata, structured raw wall-time capture,
   and pointwise plus family-wise paired sub-benchmark intervals; controlled-host acceptance remains
   experiment-level work.
3. **Proof prototype (complete):** declarative candidates, exact LLVM source/target validation,
   fail-closed resource and diagnostic handling, and compositional proof support against rustc's
   LLVM 22; candidate-to-pass generation remains future work.
4. **Pass prototype (complete):** tested, idempotent, solver-proven LLVM peephole passes.
5. **Optimizer integration (complete):** build rustc with the accepted pass and use it for retained
   exploratory redb A/B benchmark experiments.
6. **Automated search:** let the LLM and coding agent propose, disprove or prove, implement, and
   benchmark candidates with auditable artifacts and human review gates.
