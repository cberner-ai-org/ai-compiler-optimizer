.PHONY: init check test toolchain-image benchmark-image benchmark

init:
	./scripts/init-submodules.sh

check:
	./scripts/check.sh

test: check

toolchain-image:
	./scripts/build-image.sh toolchain

benchmark-image:
	./scripts/build-image.sh redb-benchmark

benchmark:
	./scripts/run-redb-benchmark.sh
