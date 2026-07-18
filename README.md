# ai-compiler-optimizer

[![CI](https://github.com/cberner-ai-org/ai-compiler-optimizer/actions/workflows/ci.yml/badge.svg)](https://github.com/cberner-ai-org/ai-compiler-optimizer/actions/workflows/ci.yml)

This repository experiments with generating small LLVM optimizations, proving
them equivalent with a solver, and measuring them against real Rust programs.
The initial performance target is [redb](https://github.com/cberner/redb).

The current scaffold builds an editable, pinned Rust compiler, attaches a
loadable no-op LLVM keyhole pass, and uses that compiler path to compile a
pinned redb benchmark. The pass changes no IR yet; it establishes the insertion
point for later solver-proven rewrites. See the [design document](docs/design.md)
for the planned architecture and safety model.

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
`library/backtrace` submodule. It deliberately avoids the large LLVM checkout:
the stage-1 compiler uses Rust's matching CI-built LLVM, and the keyhole plugin
is compiled against the headers and flags in that same archive.

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
`libaco_keyhole_pass.so` against rustc's exact LLVM, and compiles and runs a
smoke program through the pass. Its persistent build cache makes subsequent
compiler edits incremental; pass-only edits do not rebuild rustc.

The custom sysroot does not build Cargo. Cargo 1.97.1 from the pinned official
image acts only as the orchestrator, with `RUSTC` fixed to
`rustc-with-keyhole`. That wrapper invokes the custom compiler with
`-Zllvm-plugins=/opt/rust-custom/lib/libaco_keyhole_pass.so` and
`-Cpasses=aco-keyhole`.

Each toolchain build records an identity derived from the Rust source,
bootstrap configuration, and built optimizer plugin. Before compiling redb,
`with-custom-toolchain` combines that identity with the `rustc`,
`librustc_driver`, plugin, and wrapper artifacts and adds it to Cargo's tracked
compiler flags. This prevents the persistent target cache from reusing
benchmark artifacts after compiler or pass changes even though the pinned
`rustc -vV` commit remains unchanged. An image-build regression independently
checks rustc-only, driver-only, and plugin-only mutations.

## Build and run the redb benchmark

```console
make benchmark-image
make benchmark
```

The benchmark image build verifies the custom sysroot, runs redb's library
tests, and compiles `redb_benchmark` through the keyhole wrapper. The target
cache may contain outputs from several compiler identities, so installation
uses the executable path emitted by the current Cargo invocation rather than
directory timestamps.

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
- `optimizer`: LLVM 22 new-pass-manager plugin and its focused build helper
- `config/rust-bootstrap.toml`: stage-1 compiler build configuration
- `config/redb-Cargo.lock`: pinned benchmark dependency graph
- `containers/Containerfile`: compiler, toolchain, and benchmark image stages
- `scripts/rustc-with-keyhole.sh`: rustc wrapper that loads and schedules the pass
- `scripts/check.sh`: revision and scaffolding consistency checks
- `scripts/build-image.sh`: Podman image build entry point
- `docs/design.md`: architecture, safety model, and project milestones

## License

Licensed under the [MIT License](LICENSE).
