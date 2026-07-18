# ai-compiler-optimizer

[![CI](https://github.com/cberner-ai-org/ai-compiler-optimizer/actions/workflows/ci.yml/badge.svg)](https://github.com/cberner-ai-org/ai-compiler-optimizer/actions/workflows/ci.yml)

This repository experiments with generating small LLVM optimizations, proving
them equivalent with a solver, and measuring them against real Rust programs.
The initial performance target is [redb](https://github.com/cberner/redb).

The current baseline builds an editable, pinned Rust compiler and uses it to
compile a pinned redb benchmark. It intentionally contains no custom optimizer
yet. See the [design document](docs/design.md) for the planned architecture and
safety model.

The source inputs are Git submodules pinned to:

- Rust 1.97.1 at `8bab26f4f68e0e26f0bb7960be334d5b520ea452`
- redb 4.1.0 at `6ed1f981ba4deab0b2adbdd7bccb46ec409b2191`

Because redb is a library and does not commit a workspace lockfile, this
repository tracks `config/redb-Cargo.lock` for the benchmark's transitive
dependencies. It was generated with Cargo 1.97.1 while respecting redb's Rust
1.89 compatibility declaration.

## Prerequisites

- Git
- GNU Make
- ripgrep
- Rootless Podman 4.9 or newer
- At least 15 GiB of available storage for compiler and benchmark builds
- Network access on the first build for images, bootstrap artifacts, and crates

[`just`](https://github.com/casey/just) is optional; its recipes delegate to the
same Make targets documented below.

The full redb benchmark configures a 4 GiB database cache, loads five million
items, and can run for several minutes. Run it on an otherwise idle host when
collecting useful numbers.

## Initialize and check the sources

```console
make init
make test
```

`make init` fetches the two top-level submodules and only Rust's nested
`library/backtrace` submodule. It deliberately avoids the large LLVM checkout
because the bootstrap configuration uses Rust's matching CI-built LLVM.

The redb worktree must remain clean so the benchmark source exactly matches its
declared revision. The Rust worktree intentionally remains editable for compiler
development.

## Build the custom compiler toolchain

```console
make toolchain-image
podman run --rm localhost/ai-compiler-optimizer-toolchain:rust-1.97.1
```

The `toolchain` image stage builds `./x build --stage 1 library`, copies the
stage-1 compiler and standard-library sysroot to `/opt/rust-custom`, and compiles
and runs a smoke program. Its persistent build cache makes subsequent compiler
edits incremental.

The custom sysroot does not build Cargo. Cargo 1.97.1 from the pinned official
image acts only as the orchestrator, with `RUSTC` fixed to the custom compiler.

Each compiler build records an identity derived from the Rust source and
bootstrap configuration. Before compiling redb, `with-custom-toolchain` combines
that identity with the `rustc` and `librustc_driver` artifacts and adds it to
Cargo's tracked compiler flags. This prevents the persistent target cache from
reusing benchmark artifacts after compiler changes even though the pinned
`rustc -vV` commit remains unchanged. An image-build regression independently
checks rustc-only and driver-only mutations.

## Build and run the redb benchmark

```console
make benchmark-image
make benchmark
```

The benchmark image build verifies the custom sysroot, runs redb's library
tests, and compiles `redb_benchmark`. The target cache may contain outputs from
several compiler identities, so installation uses the executable path emitted
by the current Cargo invocation rather than directory timestamps.

The final image contains the custom toolchain and benchmark executable but none
of their build trees. Pass Podman options through the runner when controlling
the benchmark environment:

```console
./scripts/run-redb-benchmark.sh --cpuset-cpus=2-5
```

The compiler, Cargo registry, and Cargo target directories use named Podman
build caches. If a bootstrap configuration change requires a clean compiler
build, change the versioned rustc cache ID in `containers/Containerfile` after
deciding whether the old cache should be retained.

## Layout

- `third_party/rust`: editable Rust compiler submodule
- `third_party/redb`: pinned benchmark submodule
- `config/rust-bootstrap.toml`: stage-1 compiler build configuration
- `config/redb-Cargo.lock`: pinned benchmark dependency graph
- `containers/Containerfile`: compiler, toolchain, and benchmark image stages
- `scripts/check.sh`: revision and scaffolding consistency checks
- `scripts/build-image.sh`: Podman image build entry point
- `docs/design.md`: architecture, safety model, and project milestones

## License

Licensed under the [MIT License](LICENSE).
