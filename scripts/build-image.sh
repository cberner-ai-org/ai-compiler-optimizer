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
    proof-checker)
        image="${ALIVE2_IMAGE}"
        ;;
    toolchain)
        image="${TOOLCHAIN_IMAGE}"
        ;;
    redb-benchmark)
        image="${REDB_BENCHMARK_IMAGE}"
        ;;
    *)
        echo \
            "usage: $0 [proof-checker|toolchain|redb-benchmark] [podman build options...]" \
            >&2
        exit 2
        ;;
esac

"${repo_root}/scripts/validate-build-options.sh" "$@"

"${repo_root}/scripts/check.sh"

exec podman build \
    "$@" \
    --file "${repo_root}/containers/Containerfile" \
    --target "${target}" \
    --tag "${image}" \
    --build-arg "RUST_IMAGE=${RUST_IMAGE}" \
    --build-arg "RUST_VERSION=${RUST_VERSION}" \
    --build-arg "RUST_COMMIT=${RUST_COMMIT}" \
    --build-arg "REDB_VERSION=${REDB_VERSION}" \
    --build-arg "REDB_COMMIT=${REDB_COMMIT}" \
    --build-arg "ALIVE2_COMMIT=${ALIVE2_COMMIT}" \
    --build-arg "DEBIAN_SNAPSHOT=${DEBIAN_SNAPSHOT}" \
    --build-arg "BUILD_ENVIRONMENT_ID=${BUILD_ENVIRONMENT_ID}" \
    "${repo_root}"
