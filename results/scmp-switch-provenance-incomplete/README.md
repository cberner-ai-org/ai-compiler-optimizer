# Provenance-incomplete exploratory run

This retained seven-pair run predates the Cargo provenance correction. Its
`raw.log` records `cargo_sha256` as
`4acc9acc76d5079515b46346a485974457b5a79893cfb01112423c89aeb5aa10`,
which is the rustup dispatch proxy, and has no `cargo_proxy_sha256` field. The
selected Cargo 1.97.1 executable used by the corrected harness hashes to
`828980723df339d62434390e9fb8ef8831036583343ae2316b7ab5646b5c1953`.

The CPU vendor/model, benchmark hashes, raw timings, and corrected
multiple-comparison statistics are retained for historical inspection. This
run is provenance-incomplete and exploratory; it must not be used as
confirmatory performance evidence or described as metadata-complete.
