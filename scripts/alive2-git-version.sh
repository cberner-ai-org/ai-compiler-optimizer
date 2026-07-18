#!/usr/bin/env bash
set -euo pipefail

# The container build intentionally excludes submodule Git metadata. Preserve
# Alive2's version output by answering only the describe query used by CMake.
if [[ "${1:-}" == "describe" ]]; then
    printf '%s\n' "${ALIVE2_COMMIT:?ALIVE2_COMMIT must identify the pinned Alive2 source}"
    exit 0
fi

exec /usr/bin/git "$@"
