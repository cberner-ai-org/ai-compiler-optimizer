#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/versions.env
source "${repo_root}/config/versions.env"

# Proof inputs are embedded while building the pinned image. Disable networking
# during the rerun so verification depends only on those captured artifacts.
exec podman run --rm --network none "$@" "${ALIVE2_IMAGE}"
