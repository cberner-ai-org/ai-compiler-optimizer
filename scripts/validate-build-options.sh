#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "Podman build option validation: $*" >&2
    exit 2
}

# Build inputs are repository-owned. Only options that control resource use,
# local caching, retries, pulling the digest-pinned base, or log visibility are
# safe passthroughs. Everything else must be reviewed and added explicitly.
expected_value=""
for option in "$@"; do
    if [[ -n "${expected_value}" ]]; then
        expected_value=""
        continue
    fi

    case "${option}" in
        --cpu-period|--cpu-quota|--cpu-shares|-c|--cpuset-cpus|--cpuset-mems|--jobs|--logfile|--memory|-m|--memory-swap|--retry|--retry-delay|--shm-size|--ulimit)
            expected_value="${option}"
            ;;
        --cpu-period=*|--cpu-quota=*|--cpu-shares=*|-c?*|--cpuset-cpus=*|--cpuset-mems=*|--jobs=*|--logfile=*|--memory=*|-m?*|--memory-swap=*|--retry=*|--retry-delay=*|--shm-size=*|--ulimit=*)
            ;;
        --force-rm|--force-rm=*|--layers|--layers=*|--no-cache|--pull|--pull=*|--quiet|-q|--rm|--rm=*|--skip-unused-stages|--skip-unused-stages=*)
            ;;
        *)
            fail "${option} is not allowlisted because build inputs are pinned by config/versions.env"
            ;;
    esac
done

[[ -z "${expected_value}" ]] || fail "${expected_value} requires a value"
