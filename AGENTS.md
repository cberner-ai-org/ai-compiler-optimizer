# Agent instructions for ai-compiler-optimizer

This repository experiments with solver-verified LLVM peephole optimizations for Rust programs.
Read `docs/design.md` before making architectural changes.

## Setup

Git, GNU Make, ripgrep, and rootless Podman are required. Run `make init` to fetch the pinned Rust,
redb, and Alive2 submodules, then `make test` before building images. `just` is an optional
compatibility front end for the same Make targets.

The compiler, Cargo registry, and benchmark target directories use named Podman build caches. The
redb submodule is an immutable benchmark input and must remain clean; the Rust submodule is editable
compiler source.

## Before completing a task

Always run `make test`. After compiler or container changes, build the affected image and confirm its
embedded smoke and regression checks pass. Run `make benchmark` after changes that can affect the
compiled benchmark or measurement workflow.

Run `make prove` after Alive2, proof-adapter, candidate, or optimizer-proof changes. Do not accept a
candidate on a timeout, diagnostic, unsupported operation, or any result other than an unqualified
Alive2 refinement proof.

Do not bypass failed checks. Document any check that cannot run and the reason.

## Style

- Keep comments focused on invariants, architecture, or other long-lived context.
- Prefer small, reviewable optimization passes with explicit proof obligations.
- Treat solver timeouts, unknown results, and unsupported semantics as failed proofs.

## Git commits

Use the coding agent's configured default authorship. Do not rewrite commits to use a human author
or add an authorship compliance check.
