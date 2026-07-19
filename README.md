# ai-compiler-optimizer

[![CI](https://github.com/cberner-ai-org/ai-compiler-optimizer/actions/workflows/ci.yml/badge.svg)](https://github.com/cberner-ai-org/ai-compiler-optimizer/actions/workflows/ci.yml)

This repository experiments with generating small LLVM optimizations, proving
them equivalent with a solver, and measuring them against real Rust programs.
The initial performance target is [redb](https://github.com/cberner/redb).

The project builds an editable, pinned Rust compiler, attaches a loadable LLVM
optimization pipeline, checks declarative rewrite obligations with a pinned
Alive2 solver image, and compiles paired redb benchmarks with that pipeline
disabled and enabled. Its first transforming pass removes redundant signed
three-way comparison normalization from redb's hot B-tree searches. See the
[optimization report](docs/optimizations/scmp-switch-optimization-report.md) for its proof,
implementation boundary, and corrected exploratory measurements, and the
[design document](docs/design.md) for the architecture and safety model.

The source inputs are Git submodules pinned to:

- Rust 1.97.1 at `8bab26f4f68e0e26f0bb7960be334d5b520ea452`
- redb 4.1.0 at `6ed1f981ba4deab0b2adbdd7bccb46ec409b2191`
- Alive2 at `1d1bc4fe3135492a8c1166838c776530de479420`

The native build environment is pinned too. `config/versions.env` identifies the
Rust Bookworm image by registry digest and fixes apt to Debian snapshot
`20260713T000000Z`. An enforced ID derived from both pins scopes mutable build
caches, participates in the compiler identity, and is retained with the pins in
image labels. Updating either pin therefore selects fresh compiler and benchmark
target caches and requires rebuilding baseline and experimental artifacts
together.

Because redb is a library and does not commit a workspace lockfile, this
repository tracks `config/redb-Cargo.lock` for the benchmark's transitive
dependencies. It was generated with Cargo 1.97.1 while respecting redb's Rust
1.89 compatibility declaration.

## Prerequisites

- Git
- GNU Make
- GNU awk
- ripgrep
- Rootless Podman 4.9 or newer
- At least 15 GiB of available storage for compiler and benchmark builds
- Network access on the first build for images, bootstrap artifacts, and crates

[`just`](https://github.com/casey/just) is optional; its recipes delegate to the
same Make targets documented below.

Each full redb benchmark configures a 4 GiB database cache, loads five million
items, and can run for several minutes. The comparison runs both variants, so
allow at least twice the time and run it on an otherwise idle host when
collecting useful numbers.

## Initialize and check the sources

```console
make init
make test
```

`make init` fetches the three top-level submodules and only Rust's nested
`library/backtrace` submodule. It deliberately avoids the large LLVM checkout:
the stage-1 compiler uses Rust's matching CI-built LLVM, and the keyhole plugin
is compiled against the headers and flags in that same archive.

## Prove optimizer candidates

```console
make prove
```

The `proof-checker` image builds the pinned
[Alive2](https://github.com/AliveToolkit/alive2) `alive` verifier against Z3 packages from the pinned
Debian snapshot. It checks each `optimizer/proofs/*.opt` refinement obligation with poison and undef
inputs enabled, a 10-second SMT-query timeout, a 30-second process timeout, and a 1 GiB solver memory
limit. A proof is accepted only when one transformation reports success and the verifier emits no
diagnostics. Parse errors, type errors, counterexamples, warnings, timeouts, resource failures,
unsupported semantics, and ambiguous multi-transformation files all fail closed. The image build
also checks every negative candidate independently and requires exactly one clean Alive2 semantic
counterexample; extra diagnostics or a nonzero solver status reject the negative control.

The initial `scaffold-identity.opt` is an end-to-end solver smoke test, not a
transforming optimization. `scmp-i64-switch-classification.opt` proves the
accepted staged three-way comparison rewrite, and
`scmp-i64-switch-undef-correlation.opt` covers reused undef-capable operands
explicitly. Add one candidate per `.opt` file. A pass rewrite must be generated
from, or structurally checked against, the same candidate that Alive2 proves;
this prototype does not claim that an independent C++ implementation is
equivalent merely because a similar formula was proved.

Alive2 was selected based on its [PLDI 2021 bounded translation-validation
paper](https://doi.org/10.1145/3453483.3454030) and its use as a formal
correctness gate in [LLM-Vectorizer](https://arxiv.org/abs/2406.04693).

The redb worktree must remain clean so the benchmark source exactly matches its
declared revision. The Rust worktree intentionally remains editable for compiler
development.

## Build the custom compiler toolchain

```console
make toolchain-image
podman run --rm localhost/ai-compiler-optimizer-toolchain:rust-1.97.1
```

The `toolchain` image stage builds `./x build --stage 1 library`, copies the
stage-1 compiler and standard-library sysroot to `/opt/rust-custom`, builds
`libaco_optimizer.so` against rustc's exact LLVM, runs the focused pass
regression with that LLVM's `opt`, and compiles and runs a smoke program both
without and with the pass pipeline. Its persistent build cache makes subsequent
compiler edits incremental; pass-only edits do not rebuild rustc.

The custom sysroot does not build Cargo. Cargo 1.97.1 from the digest-pinned
official image acts only as the orchestrator. `with-compiler-variant baseline`
sets `RUSTC` to the unmodified stage-1 compiler invocation;
`with-compiler-variant optimized` selects `rustc-with-aco-passes`, which adds
`-Zllvm-plugins=/opt/rust-custom/lib/libaco_optimizer.so` and
`-Cpasses=aco-passes`.

After assembling the toolchain, the image generates one compiler-artifact
manifest and ID covering the compiler source identity, `rustc`,
`librustc_driver`, `libLLVM`, and the complete sysroot. Both
`with-compiler-variant` and benchmark provenance consume that precomputed ID;
they do not reconstruct subsets of compiler inputs. The optimized variant adds
the plugin and rustc wrapper to its identity, then selects a separate Cargo
target directory. This prevents stale cache reuse without identity-only rustc
flags that could change symbol names or binary layout. An image regression
checks rustc-, driver-, LLVM-, sysroot-, plugin-, and wrapper-only mutations and
confirms pass-only changes leave the baseline cache fresh.

## Build and run the redb benchmark

```console
make benchmark-image
make benchmark
```

The benchmark image build verifies the custom sysroot, runs redb's library
tests in both compiler modes, and compiles a focused redb byte-slice probe from
separate fresh baseline and optimized targets with tracing enabled. The
baseline probe must emit no ACO trace, while the optimized probe must emit at
least one transforming trace, before the image compiles `redb_benchmark`
twice. The baseline artifact uses the stage-1 compiler without custom pass
flags; the optimized
artifact uses the same compiler with the ACO pipeline enabled. The target cache
may contain outputs from several compiler identities, so each installation uses
the executable path emitted by its current Cargo invocation rather than
directory timestamps.

The final runtime image excludes the custom compiler and both build trees. The
benchmark-builder first assembles both executables, the A/B runner, and the
clock helper, then generates provenance over that complete runtime bundle; the
final stage copies those exact files together. One round runs baseline then
optimized; later rounds reverse the order to reduce ordering bias. Output from
each benchmark is labeled, and the final table compares total wall time with
positive percentages meaning the optimized variant was faster. Elapsed samples
come from `clock_gettime(CLOCK_MONOTONIC)`;
the runner rejects non-positive samples and reports both online CPU count and
the effective affinity list/count inherited by the benchmarks, plus CPU vendor
and model from `/proc/cpuinfo`. The clock helper is built from repository source
and recorded in the provenance manifest. One round is a plumbing check, not
statistically meaningful evidence. Set
`ACO_BENCHMARK_RUNS` through Podman for repeated measurements, and pass other
Podman options through the runner when controlling the environment:

```console
./scripts/run-redb-benchmark.sh --cpuset-cpus=2-5 --env ACO_BENCHMARK_RUNS=3
```

To retain the raw per-run wall times, mount an output directory and select a
result path inside it:

```console
./scripts/run-redb-benchmark.sh \
  --volume "$PWD/results:/results:Z" \
  --env ACO_BENCHMARK_RESULTS=/results/redb.tsv
```

The compiler and Cargo target directories use environment-scoped Podman build
caches. The Cargo registry cache is shared across environments because locked
crate downloads are content-addressed and checksum-verified. Bootstrap and
source changes keep using the current environment's incremental compiler cache;
changing either native environment pin automatically selects fresh mutable
caches. `build-image.sh` applies a deny-by-default option allowlist: callers may
control resource limits, local cache use, retries, pulling the digest-pinned
base, and log visibility. Every unclassified option is rejected, including
environment injection, build arguments, named build contexts, labels, source
mounts, alternate Containerfiles or stages, base-image replacement, and target
platform changes.

The benchmark runtime embeds
`/usr/local/share/ai-compiler-optimizer/benchmark-provenance.tsv`. It records the
compiler artifact ID, hashes of rustc, its driver set, LLVM and sysroot, the
optimizer plugin and wrappers, the Cargo executable selected by rustup and its
dispatch proxy, the redb revision and lockfile, both benchmark binaries, the
comparison runner, and the pinned native environment.
The runner verifies itself, the clock, and both binaries before printing the
complete manifest and starting an experiment.

## Layout

- `third_party/rust`: editable Rust compiler submodule
- `third_party/redb`: pinned benchmark submodule
- `third_party/alive2`: pinned LLVM refinement checker submodule
- `optimizer`: aggregate LLVM 22 new-pass-manager plugin and proof obligations
- `optimizer/proofs`: declarative Alive2 candidate and scaffold obligations
- `config/rust-bootstrap.toml`: stage-1 compiler build configuration
- `config/redb-Cargo.lock`: pinned benchmark dependency graph
- `containers/Containerfile`: compiler, toolchain, and benchmark image stages
- `scripts/with-compiler-variant.sh`: cache-safe baseline/optimized Cargo selector
- `scripts/write-compiler-artifact-manifest.sh`: complete toolchain identity owner
- `scripts/rustc-with-aco-passes.sh`: rustc wrapper that loads the custom pass pipeline
- `scripts/compare-redb-benchmarks.sh`: alternating paired redb benchmark runner
- `scripts/summarize-redb-subbenchmarks.sh`: pointwise and family-wise paired statistics
- `scripts/verify-alive2-proofs.sh`: fail-closed proof-result adapter
- `scripts/verify-alive2-negative-proofs.sh`: exact negative-control result adapter
- `scripts/check.sh`: revision and scaffolding consistency checks
- `scripts/build-image.sh`: Podman image build entry point
- `scripts/validate-build-options.sh`: safe Podman build-option allowlist
- `docs/design.md`: architecture, safety model, and project milestones
- `docs/optimizations/scmp-switch-optimization-report.md`: accepted pass proof and benchmark report

## License

Licensed under the [MIT License](LICENSE).
