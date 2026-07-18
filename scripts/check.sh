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
check_clean_worktree "${repo_root}/third_party/redb" "redb"

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
rg --quiet --fixed-strings "ARG RUST_VERSION=${RUST_VERSION}" \
    "${repo_root}/containers/Containerfile" \
    || fail "Containerfile Rust version does not match config/versions.env"
rg --quiet --fixed-strings "ARG RUST_COMMIT=${RUST_COMMIT}" \
    "${repo_root}/containers/Containerfile" \
    || fail "Containerfile Rust commit does not match config/versions.env"
rg --quiet --fixed-strings "with-custom-toolchain cargo test" \
    "${repo_root}/containers/Containerfile" \
    || fail "redb tests do not use the compiler-aware Cargo wrapper"
rg --quiet --fixed-strings "libaco_keyhole_pass.so" \
    "${repo_root}/containers/Containerfile" \
    || fail "Containerfile does not install the keyhole pass plugin"
rg --quiet --fixed-strings "RUSTC=/usr/local/bin/rustc-with-keyhole" \
    "${repo_root}/containers/Containerfile" \
    || fail "container Cargo builds do not use the keyhole rustc wrapper"
rg --quiet --fixed-strings "build-redb-benchmark" \
    "${repo_root}/containers/Containerfile" \
    || fail "redb benchmark does not use Cargo-reported artifact selection"
rg --quiet --fixed-strings "ripgrep" "${repo_root}/README.md" \
    || fail "README prerequisites do not document ripgrep"

for git_pointer in \
    third_party/rust/.git \
    third_party/rust/library/backtrace/.git \
    third_party/redb/.git; do
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
"${repo_root}/tests/cargo-artifact-selection.sh"
"${repo_root}/tests/rustc-keyhole-wrapper.sh"

git -C "${repo_root}" diff --check
echo "scaffolding checks passed"
