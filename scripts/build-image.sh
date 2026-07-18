#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/versions.env
source "${repo_root}/config/versions.env"

target="${1:-redb-benchmark}"
if [[ $# -gt 0 ]]; then
    shift
fi

case "${target}" in
    toolchain)
        image="${TOOLCHAIN_IMAGE}"
        ;;
    redb-benchmark)
        image="${REDB_BENCHMARK_IMAGE}"
        ;;
    *)
        echo "usage: $0 [toolchain|redb-benchmark] [podman build options...]" >&2
        exit 2
        ;;
esac

"${repo_root}/scripts/check.sh"

exec podman build \
    --file "${repo_root}/containers/Containerfile" \
    --target "${target}" \
    --tag "${image}" \
    --build-arg "RUST_IMAGE=${RUST_IMAGE}" \
    --build-arg "RUST_VERSION=${RUST_VERSION}" \
    --build-arg "RUST_COMMIT=${RUST_COMMIT}" \
    "$@" \
    "${repo_root}"
