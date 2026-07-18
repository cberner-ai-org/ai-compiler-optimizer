#!/usr/bin/env bash
set -euo pipefail

readonly REDB_REPOSITORY="${REDB_REPOSITORY:-https://github.com/cberner/redb.git}"
readonly REDB_REVISION="${REDB_REVISION:-master}"
readonly CHECKOUT=/work/redb

mkdir -p "$CHECKOUT" /cache/cargo /cache/target

git -C "$CHECKOUT" init --quiet
git -C "$CHECKOUT" remote add origin "$REDB_REPOSITORY"
git -C "$CHECKOUT" fetch --quiet --depth=1 origin "$REDB_REVISION"
git -C "$CHECKOUT" checkout --quiet --detach FETCH_HEAD

echo "Benchmarking redb commit $(git -C "$CHECKOUT" rev-parse HEAD)"

cd "$CHECKOUT"
export CARGO_HOME=/cache/cargo
export CARGO_TARGET_DIR=/cache/target
export RUSTUP_TOOLCHAIN=1.90.0

cargo bench -p redb-bench --bench redb_benchmark
