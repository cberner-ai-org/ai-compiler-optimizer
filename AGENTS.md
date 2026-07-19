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

## Disk space

- Monitor free space on the filesystems backing the workspace, temporary directories, and container
  storage before and after disk-intensive builds, tests, benchmarks, image operations, or large
  dependency fetches. Recheck periodically while long-running work is producing data.
- Keep at least 20% of each affected filesystem free at all times. Begin cleanup before free space
  falls below 25% to preserve a safety margin. If free space is already below 20%, pause
  disk-consuming work and restore the minimum before continuing.
- Proactively prune stale, regenerable data as work progresses, including abandoned build
  artifacts, obsolete compiler and benchmark caches, stopped containers, unused container images,
  and expired temporary or test output. Do not wait for the filesystem to become critically full.
- Before pruning shared caches or container storage, verify that no active process, mount, lock, or
  in-progress build is using the data. Prefer narrowly scoped cleanup and verify free space again
  afterward.
- Never delete source files, uncommitted work, intentionally retained results, or data owned by an
  active process. If safe stale-data cleanup cannot maintain 20% free space, stop and report the
  blocker rather than risking user data or active work.

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
