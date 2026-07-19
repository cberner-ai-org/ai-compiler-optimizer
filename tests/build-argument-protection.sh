#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
validator="${repo_root}/scripts/validate-build-options.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf -- "${fixture_root}"' EXIT

expect_rejected_override() {
    local label="$1"
    shift
    local log_path="${fixture_root}/${label}.log"

    if "${repo_root}/scripts/build-image.sh" redb-benchmark "$@" \
        > "${log_path}" 2>&1; then
        echo "protected build input override was accepted: ${label}" >&2
        exit 1
    fi
    grep --quiet --fixed-strings \
        "pinned by config/versions.env" \
        "${log_path}"
}

expect_rejected_override separate \
    --build-arg BUILD_ENVIRONMENT_ID=qa-override
expect_rejected_override equals \
    --build-arg=DEBIAN_SNAPSHOT=19700101T000000Z
expect_rejected_override inherited \
    --build-arg RUST_IMAGE

expect_rejected_override env-separate \
    --env ALIVE2_COMMIT=qa-override
expect_rejected_override env-equals \
    --env=RUST_COMMIT=qa-override
expect_rejected_override env-short \
    -eREDB_COMMIT=qa-override
expect_rejected_override env-short-separate \
    -e BUILD_ENVIRONMENT_ID
expect_rejected_override unsetenv \
    --unsetenv DEBIAN_SNAPSHOT
expect_rejected_override rustflags \
    --env 'RUSTFLAGS=-Zllvm-plugins=/opt/rust-custom/lib/libaco_optimizer.so -Cpasses=aco-passes'
expect_rejected_override encoded-rustflags \
    --env=CARGO_ENCODED_RUSTFLAGS=-Copt-level=0
expect_rejected_override arbitrary-environment \
    --env QA_UNTRACKED_BUILD_INPUT=1

printf 'ALIVE2_COMMIT=qa-override\n' > "${fixture_root}/override.env"
expect_rejected_override env-file \
    --env-file "${fixture_root}/override.env"
expect_rejected_override build-arg-file \
    --build-arg-file "${fixture_root}/override.env"
expect_rejected_override env-host \
    --env-host

expect_rejected_override label \
    --label org.cberner-ai.ai-compiler-optimizer.redb-commit=qa-override
expect_rejected_override label-file \
    --label-file "${fixture_root}/override.env"
expect_rejected_override unset-label \
    --unsetlabel org.cberner-ai.ai-compiler-optimizer.build-environment-id
expect_rejected_override base-image \
    --from qa-override
expect_rejected_override build-volume \
    --volume "${fixture_root}:/usr/src/alive2"
expect_rejected_override target-platform \
    --platform linux/arm64
expect_rejected_override named-build-context \
    --build-context alive2-builder=container-image://qa-override
expect_rejected_override named-build-context-equals \
    --build-context=rustc-builder=container-image://qa-override

"${validator}" \
    --no-cache \
    --jobs=2 \
    --memory 4g \
    --pull=never \
    --retry 1 \
    --quiet

echo "build option allowlist regression passed"
