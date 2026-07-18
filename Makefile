.PHONY: init check test solver-image prove toolchain-image benchmark-image benchmark

init:
	./scripts/init-submodules.sh

check:
	./scripts/check.sh

test: check

solver-image:
	./scripts/build-image.sh proof-checker

prove: solver-image
	./scripts/run-alive2-proofs.sh

toolchain-image:
	./scripts/build-image.sh toolchain

benchmark-image:
	./scripts/build-image.sh redb-benchmark

benchmark:
	./scripts/run-redb-benchmark.sh
