#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/versions.env
source "${repo_root}/config/versions.env"

# Additional arguments are Podman run options, for example:
#   ./scripts/run-redb-benchmark.sh --cpuset-cpus=2-5
exec podman run --rm "$@" "${REDB_BENCHMARK_IMAGE}"
