init:
    make init

test:
    make test

toolchain_image:
    make toolchain-image

benchmark_image:
    make benchmark-image

bench_redb:
    make benchmark-image
    make benchmark
