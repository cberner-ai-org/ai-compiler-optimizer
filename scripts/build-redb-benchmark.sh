#!/usr/bin/env bash
set -euo pipefail

messages_file="$(mktemp)"
trap 'rm -f -- "${messages_file}"' EXIT

# Keep Cargo's human progress and diagnostics streaming on stderr while
# retaining this invocation's JSON event stream as the sole authority for
# executable selection.
set +e
with-custom-toolchain cargo bench \
    --locked \
    --no-run \
    --package redb-bench \
    --bench redb_benchmark \
    --message-format=json-render-diagnostics \
    | tee "${messages_file}" > /dev/null
pipeline_status=("${PIPESTATUS[@]}")
set -e

(( pipeline_status[0] == 0 )) \
    || exit "${pipeline_status[0]}"
(( pipeline_status[1] == 0 )) \
    || exit "${pipeline_status[1]}"

benchmark_path="$(
    select-cargo-executable redb_benchmark < "${messages_file}"
)"
[[ -x "${benchmark_path}" ]] \
    || { echo "Cargo-reported benchmark is not executable: ${benchmark_path}" >&2; exit 1; }

install --mode 0755 "${benchmark_path}" /usr/local/bin/redb-benchmark
echo "installed Cargo-reported benchmark: ${benchmark_path}"
