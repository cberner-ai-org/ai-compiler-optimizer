#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/versions.env
source "${repo_root}/config/versions.env"

fail() {
    echo "check failed: $*" >&2
    exit 1
}

check_revision() {
    local path="$1"
    local expected="$2"
    local label="$3"

    [[ -e "${path}/.git" ]] || fail "${label} submodule is not initialized"

    local actual
    actual="$(git -C "${path}" rev-parse HEAD)"
    [[ "${actual}" == "${expected}" ]] \
        || fail "${label} is at ${actual}; expected ${expected}"
}

check_clean_worktree() {
    local path="$1"
    local label="$2"
    local worktree_status

    worktree_status="$(
        git -C "${path}" status \
            --porcelain=v1 \
            --untracked-files=all \
            --ignore-submodules=none
    )"
    if [[ -n "${worktree_status}" ]]; then
        echo "${label} worktree changes:" >&2
        printf '%s\n' "${worktree_status}" >&2
        fail "${label} worktree must be clean because it is a pinned build input"
    fi
}

check_revision "${repo_root}/third_party/rust" "${RUST_COMMIT}" "Rust"
check_revision "${repo_root}/third_party/redb" "${REDB_COMMIT}" "redb"
check_revision "${repo_root}/third_party/alive2" "${ALIVE2_COMMIT}" "Alive2"
check_clean_worktree "${repo_root}/third_party/redb" "redb"
check_clean_worktree "${repo_root}/third_party/alive2" "Alive2"

expected_backtrace="$(git -C "${repo_root}/third_party/rust" ls-tree HEAD library/backtrace | awk '{print $3}')"
check_revision \
    "${repo_root}/third_party/rust/library/backtrace" \
    "${expected_backtrace}" \
    "Rust backtrace"

expected_commit_info="${RUST_COMMIT}"$'\n'"${RUST_SHORT_COMMIT}"$'\n'"${RUST_COMMIT_DATE}"
actual_commit_info="$(<"${repo_root}/config/rust-git-commit-info")"
[[ "${actual_commit_info}" == "${expected_commit_info}" ]] \
    || fail "config/rust-git-commit-info does not match the Rust pin"

rg --quiet '^version = 4$' "${repo_root}/config/redb-Cargo.lock" \
    || fail "config/redb-Cargo.lock is missing or has an unexpected format"
rg --quiet --multiline \
    "name = \"redb\"\nversion = \"${REDB_VERSION}\"" \
    "${repo_root}/config/redb-Cargo.lock" \
    || fail "config/redb-Cargo.lock does not contain redb ${REDB_VERSION}"

rg --quiet --fixed-strings "ARG RUST_IMAGE=${RUST_IMAGE}" \
    "${repo_root}/containers/Containerfile" \
    || fail "Containerfile base image does not match config/versions.env"
[[ "${RUST_IMAGE}" =~ @sha256:[0-9a-f]{64}$ ]] \
    || fail "RUST_IMAGE must end in a sha256 registry digest"
rg --quiet --fixed-strings "ARG RUST_VERSION=${RUST_VERSION}" \
    "${repo_root}/containers/Containerfile" \
    || fail "Containerfile Rust version does not match config/versions.env"
rg --quiet --fixed-strings "ARG RUST_COMMIT=${RUST_COMMIT}" \
    "${repo_root}/containers/Containerfile" \
    || fail "Containerfile Rust commit does not match config/versions.env"
rg --quiet --fixed-strings "ARG REDB_VERSION=${REDB_VERSION}" \
    "${repo_root}/containers/Containerfile" \
    || fail "Containerfile redb version does not match config/versions.env"
rg --quiet --fixed-strings "ARG REDB_COMMIT=${REDB_COMMIT}" \
    "${repo_root}/containers/Containerfile" \
    || fail "Containerfile redb commit does not match config/versions.env"
rg --quiet --fixed-strings "ARG ALIVE2_COMMIT=${ALIVE2_COMMIT}" \
    "${repo_root}/containers/Containerfile" \
    || fail "Containerfile Alive2 commit does not match config/versions.env"
rg --quiet --fixed-strings "ARG DEBIAN_SNAPSHOT=${DEBIAN_SNAPSHOT}" \
    "${repo_root}/containers/Containerfile" \
    || fail "Containerfile Debian snapshot does not match config/versions.env"
[[ "${DEBIAN_SNAPSHOT}" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] \
    || fail "DEBIAN_SNAPSHOT must use YYYYMMDDTHHMMSSZ format"
expected_build_environment_id="$(
    printf \
        'rust-image:%s\ndebian-snapshot:%s\n' \
        "${RUST_IMAGE}" \
        "${DEBIAN_SNAPSHOT}" \
        | sha256sum \
        | awk '{print $1}'
)"
[[ "${BUILD_ENVIRONMENT_ID}" == "${expected_build_environment_id}" ]] \
    || fail "BUILD_ENVIRONMENT_ID does not match the pinned build environment"
rg --quiet --fixed-strings "ARG BUILD_ENVIRONMENT_ID=${BUILD_ENVIRONMENT_ID}" \
    "${repo_root}/containers/Containerfile" \
    || fail "Containerfile build environment ID does not match config/versions.env"
snapshot_reference_count="$(
    rg --count --fixed-strings \
        'apt-get -o Acquire::Check-Valid-Until=false update' \
        "${repo_root}/containers/Containerfile"
)"
package_install_count="$(
    rg --count --fixed-strings \
        'apt-get install --yes --no-install-recommends' \
        "${repo_root}/containers/Containerfile"
)"
[[ "${snapshot_reference_count}" == "${package_install_count}" ]] \
    || fail "every apt package installation must use the pinned Debian snapshot"
rg --quiet --fixed-strings -- \
    '--build-arg "DEBIAN_SNAPSHOT=${DEBIAN_SNAPSHOT}"' \
    "${repo_root}/scripts/build-image.sh" \
    || fail "image builds do not pass the configured Debian snapshot"
rg --quiet --fixed-strings -- \
    '--build-arg "BUILD_ENVIRONMENT_ID=${BUILD_ENVIRONMENT_ID}"' \
    "${repo_root}/scripts/build-image.sh" \
    || fail "image builds do not pass the configured build environment ID"
rg --quiet --fixed-strings -- \
    '--build-arg "ALIVE2_COMMIT=${ALIVE2_COMMIT}"' \
    "${repo_root}/scripts/build-image.sh" \
    || fail "image builds do not pass the configured Alive2 revision"
rg --quiet --fixed-strings -- \
    '--build-arg "REDB_COMMIT=${REDB_COMMIT}"' \
    "${repo_root}/scripts/build-image.sh" \
    || fail "image builds do not pass the configured redb revision"
passthrough_line="$(
    rg --line-number --fixed-strings '    "$@" \' \
        "${repo_root}/scripts/build-image.sh" \
        | cut -d: -f1
)"
environment_arg_line="$(
    rg --line-number --fixed-strings \
        '    --build-arg "BUILD_ENVIRONMENT_ID=${BUILD_ENVIRONMENT_ID}" \' \
        "${repo_root}/scripts/build-image.sh" \
        | cut -d: -f1
)"
[[ "${passthrough_line}" =~ ^[0-9]+$ \
    && "${environment_arg_line}" =~ ^[0-9]+$ \
    && passthrough_line -lt environment_arg_line ]] \
    || fail "configured build arguments must follow passthrough options"
rg --quiet --fixed-strings \
    'id=ai-compiler-optimizer-rust-${BUILD_ENVIRONMENT_ID}' \
    "${repo_root}/containers/Containerfile" \
    || fail "rustc build cache is not scoped to the pinned environment"
rg --quiet --fixed-strings \
    'id=ai-compiler-optimizer-redb-target-${BUILD_ENVIRONMENT_ID}' \
    "${repo_root}/containers/Containerfile" \
    || fail "redb target cache is not scoped to the pinned environment"
rg --quiet --fixed-strings \
    'build-environment:%s\n' \
    "${repo_root}/containers/Containerfile" \
    || fail "rustc build identity does not include the pinned environment"
rg --quiet --fixed-strings "with-compiler-variant baseline" \
    "${repo_root}/containers/Containerfile" \
    || fail "redb baseline does not disable custom optimization passes"
rg --quiet --fixed-strings "with-compiler-variant optimized" \
    "${repo_root}/containers/Containerfile" \
    || fail "redb optimized variant does not enable custom optimization passes"
rg --quiet --fixed-strings \
    'COPY tests/redb-ir-probe/ /usr/src/tests/redb-ir-probe/' \
    "${repo_root}/containers/Containerfile" \
    || fail "benchmark image does not compile the redb optimizer coverage probe"
rg --quiet --fixed-strings \
    "verify-redb-variant-traces" \
    "${repo_root}/containers/Containerfile" \
    || fail "benchmark image does not verify the fresh baseline/optimized traces"
rg --quiet --fixed-strings "libaco_optimizer.so" \
    "${repo_root}/containers/Containerfile" \
    || fail "Containerfile does not install the optimizer pass plugin"
rg --quiet --fixed-strings "redb-benchmark-baseline" \
    "${repo_root}/containers/Containerfile" \
    || fail "Containerfile does not retain the baseline benchmark artifact"
rg --quiet --fixed-strings "redb-benchmark-optimized" \
    "${repo_root}/containers/Containerfile" \
    || fail "Containerfile does not retain the optimized benchmark artifact"
rg --quiet --fixed-strings 'CARGO_TARGET_DIR="${target_root%/}/aco-${variant}-${variant_artifact_id}"' \
    "${repo_root}/scripts/with-compiler-variant.sh" \
    || fail "compiler variants do not select identity-scoped Cargo target directories"
if rg --quiet --fixed-strings -- '-Cmetadata=' \
    "${repo_root}/scripts/with-compiler-variant.sh"; then
    fail "compiler variant identity must not alter benchmark crate metadata"
fi
rg --quiet --fixed-strings "compare-redb-benchmarks" \
    "${repo_root}/containers/Containerfile" \
    || fail "benchmark image does not run the A/B comparison harness"
rg --quiet --fixed-strings "benchmark-provenance.tsv" \
    "${repo_root}/containers/Containerfile" \
    || fail "benchmark image does not retain its exact build provenance"
rg --quiet --fixed-strings "write-compiler-artifact-manifest" \
    "${repo_root}/containers/Containerfile" \
    || fail "toolchain does not precompute its complete compiler artifact identity"
rg --quiet --fixed-strings "llvm_library_set_sha256" \
    "${repo_root}/scripts/write-compiler-artifact-manifest.sh" \
    || fail "compiler artifact identity does not include LLVM"
rg --quiet --fixed-strings "provenance manifest sha256" \
    "${repo_root}/scripts/compare-redb-benchmarks.sh" \
    || fail "benchmark runner does not report its build provenance"
rg --quiet --fixed-strings "CPU model:" \
    "${repo_root}/scripts/compare-redb-benchmarks.sh" \
    || fail "benchmark runner does not report the CPU model"
rg --quiet --fixed-strings "comparison runner does not match the provenance manifest" \
    "${repo_root}/scripts/compare-redb-benchmarks.sh" \
    || fail "benchmark runner is not bound to its provenance manifest"
rg --quiet --fixed-strings "build-redb-benchmark" \
    "${repo_root}/containers/Containerfile" \
    || fail "redb benchmark does not use Cargo-reported artifact selection"
rg --quiet --fixed-strings "verify-alive2-proofs /opt/aco/proofs" \
    "${repo_root}/containers/Containerfile" \
    || fail "proof-checker image does not verify accepted optimizer obligations"
rg --quiet --fixed-strings -- '--network none' \
    "${repo_root}/scripts/run-alive2-proofs.sh" \
    || fail "proof reruns do not disable network access"
rg --quiet --fixed-strings "ripgrep" "${repo_root}/README.md" \
    || fail "README prerequisites do not document ripgrep"

for git_pointer in \
    third_party/rust/.git \
    third_party/rust/library/backtrace/.git \
    third_party/redb/.git \
    third_party/alive2/.git; do
    rg --quiet --fixed-strings "${git_pointer}" "${repo_root}/.containerignore" \
        || fail ".containerignore does not exclude ${git_pointer}"
done

for script in "${repo_root}"/scripts/*.sh; do
    bash -n "${script}"
done
for script in "${repo_root}"/tests/*.sh; do
    bash -n "${script}"
done
bash -n "${repo_root}/optimizer/build.sh"
bash -n "${repo_root}/optimizer/test.sh"
"${repo_root}/tests/cargo-artifact-selection.sh"
"${repo_root}/tests/alive2-proof-gate.sh"
"${repo_root}/tests/benchmark-provenance.sh"
"${repo_root}/tests/build-argument-protection.sh"
"${repo_root}/tests/compiler-variant-wrapper.sh"
"${repo_root}/tests/optimizer-proof-consistency.sh"
"${repo_root}/tests/redb-benchmark-comparison.sh"
"${repo_root}/tests/redb-subbenchmark-summary.sh"
"${repo_root}/tests/redb-variant-traces.sh"

git -C "${repo_root}" diff --check
echo "scaffolding checks passed"
