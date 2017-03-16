TESTS=\
	cache.sh \
	encode_args.sh \
	locks.sh \
	locks_critical_section.sh \
	locks_critical_section_nested.sh \
	port_var_fetch.sh \
	relpath.sh \
	relpath_common.sh \
	shash_basic.sh \
	trap_save.sh \

all: check

check: .PHONY
	@echo "Running tests against stock /bin/sh"
	@sh runtests.sh /bin/sh ${TESTS}
	@echo "Running tests against modified sh"
	@sh runtests.sh sh ${TESTS}
