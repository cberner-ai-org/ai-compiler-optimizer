#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
selector="${repo_root}/scripts/select-cargo-executable.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf -- "${fixture_root}"' EXIT

artifact_a="${fixture_root}/redb_benchmark-identity-a"
artifact_b="${fixture_root}/redb_benchmark-identity-b"
touch -t 202601010000 "${artifact_a}"
touch -t 202701010000 "${artifact_b}"

# Model A -> B -> A: both cache entries exist and B has the newest mtime, but
# the current Cargo event stream authoritatively reports the fresh A artifact.
selected="$(
    "${selector}" redb_benchmark <<EOF
{"reason":"compiler-artifact","target":{"kind":["bin"],"name":"redb_benchmark"},"executable":"${artifact_b}","fresh":true}
{"reason":"compiler-artifact","target":{"kind":["bench"],"name":"redb_benchmark"},"executable":"${artifact_a}","fresh":true}
{"reason":"build-finished","success":true}
EOF
)"

[[ "${selected}" == "${artifact_a}" ]] \
    || { echo "selected ${selected}; expected Cargo-reported ${artifact_a}" >&2; exit 1; }

echo "Cargo artifact selection regression passed"
