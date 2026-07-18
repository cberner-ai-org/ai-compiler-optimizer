#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

git -C "${repo_root}" submodule update --init --depth 1 \
    third_party/rust \
    third_party/redb

# A compiler + std build only needs this nested Rust submodule. Avoid pulling
# LLVM and the documentation/tool submodules; CI LLVM is selected in config.
git -C "${repo_root}/third_party/rust" submodule update --init --depth 1 \
    library/backtrace
