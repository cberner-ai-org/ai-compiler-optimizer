# Agent instructions for ai-compiler-optimizer

This repository experiments with solver-verified LLVM peephole optimizations for Rust programs.
Read `docs/design.md` before making architectural changes.

## Setup

`just` and rootless Podman are required. The benchmark image contains the Rust toolchain and Linux
build dependencies. Cargo downloads and build artifacts are stored in the
`ai-compiler-optimizer-redb-cache` Podman volume.

## Before completing a task

Run `just bench_redb` after changing the benchmark scaffold and confirm that it succeeds. Run the
most relevant focused checks for future compiler or solver code as those components are added.

Do not bypass failed checks. Document any check that cannot run and the reason.

## Style

- Keep comments focused on invariants, architecture, or other long-lived context.
- Prefer small, reviewable optimization passes with explicit proof obligations.
- Treat solver timeouts, unknown results, and unsupported semantics as failed proofs.

## Git commits

Use the coding agent's configured default authorship. Do not rewrite commits to use a human author
or add an authorship compliance check.
