#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

readonly IMAGE="${REDB_BENCH_IMAGE:-localhost/ai-compiler-optimizer-redb-bench:rust-1.90}"
readonly CACHE_VOLUME="${REDB_BENCH_CACHE_VOLUME:-ai-compiler-optimizer-redb-cache}"

podman build \
    --file Containerfile.redb-bench \
    --pull=missing \
    --tag "$IMAGE" \
    .

podman volume create --ignore "$CACHE_VOLUME" >/dev/null

podman run --rm \
    --volume "$CACHE_VOLUME:/cache:rw" \
    --env "REDB_REPOSITORY=${REDB_REPOSITORY:-https://github.com/cberner/redb.git}" \
    --env "REDB_REVISION=${REDB_REVISION:-master}" \
    "$IMAGE"
