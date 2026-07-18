# ai-compiler-optimizer

[![CI](https://github.com/cberner-ai-org/ai-compiler-optimizer/actions/workflows/ci.yml/badge.svg)](https://github.com/cberner-ai-org/ai-compiler-optimizer/actions/workflows/ci.yml)

An experiment in generating small LLVM optimizations and proving them equivalent with a solver
before using them to compile real programs. The initial performance target is
[redb](https://github.com/cberner/redb).

The project is currently scaffolding its baseline benchmark. It does not yet build a custom Rust
compiler or contain optimization passes. See the [design document](docs/design.md) for the planned
architecture and safety model.

## Development

Install [`just`](https://github.com/casey/just) and rootless
[`Podman`](https://podman.io/), then run:

```console
just bench_redb
```

The command builds a pinned Rust 1.90 container, checks out redb's `master` branch in the container,
and runs:

```console
cargo bench -p redb-bench --bench redb_benchmark
```

Cargo downloads and build output are retained in the `ai-compiler-optimizer-redb-cache` Podman
volume. Set `REDB_REVISION` to a branch, tag, or commit to benchmark a specific redb revision. Run
`just clear_redb_cache` when a clean build is needed.

## License

Licensed under the [MIT License](LICENSE).
