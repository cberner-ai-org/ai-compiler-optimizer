#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf -- "${fixture_root}"' EXIT

expect_rejected_override() {
    local label="$1"
    shift
    local log_path="${fixture_root}/${label}.log"

    if "${repo_root}/scripts/build-image.sh" redb-benchmark "$@" \
        > "${log_path}" 2>&1; then
        echo "protected build argument override was accepted: ${label}" >&2
        exit 1
    fi
    grep --quiet --fixed-strings \
        "is pinned by config/versions.env" \
        "${log_path}"
}

expect_rejected_override separate \
    --build-arg BUILD_ENVIRONMENT_ID=qa-override
expect_rejected_override equals \
    --build-arg=DEBIAN_SNAPSHOT=19700101T000000Z
expect_rejected_override inherited \
    --build-arg RUST_IMAGE

echo "build argument protection regression passed"
