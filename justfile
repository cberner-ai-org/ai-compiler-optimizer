bench_redb:
    ./scripts/bench-redb.sh

clear_redb_cache:
    podman volume rm --force ai-compiler-optimizer-redb-cache
