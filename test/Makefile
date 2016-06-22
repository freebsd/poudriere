TESTS=\
	locks.sh \
	relpath.sh \
	shash_basic.sh \

all: check

check: .PHONY
	@echo "Running tests against stock /bin/sh"
	@sh runtests.sh /bin/sh ${TESTS}
	@echo "Running tests against modified sh"
	@../sh runtests.sh sh ${TESTS}
