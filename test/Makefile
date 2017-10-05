TESTS=\
	cache.sh \
	encode_args.sh \
	list.sh \
	locks.sh \
	locks_critical_section.sh \
	locks_critical_section_nested.sh \
	port_var_fetch.sh \
	relpath.sh \
	relpath_common.sh \
	shash_basic.sh \
	trap_save.sh \
	bulk-bad-DEPENDS_ARGS.sh \
	bulk-flavor-default-dep-and-specific-listed.sh \
	bulk-flavor-default-dep.sh \
	bulk-flavor-main-dep-and-default-listed.sh \
	bulk-flavor-main-dep-and-specific-listed.sh \
	bulk-flavor-main-dep.sh \
	bulk-flavor-specific-dep-and-default-listed.sh \
	bulk-flavor-specific-dep-and-default-shorthand-listed.sh \
	bulk-flavor-specific-dep-and-main-listed.sh \
	bulk-flavor-specific-dep-and-multi-listed.sh \
	bulk-flavor-specific-dep-and-multi-no-main-listed.sh \
	bulk-flavor-specific-dep-and-specific-listed.sh \
	bulk-flavor-specific-dep.sh \
	bulk-flavor-all.sh

all: check

check: .PHONY
	@echo "Running tests against stock /bin/sh"
	@sh runtests.sh /bin/sh ${TESTS}
	@echo
	@echo "Running tests against modified sh"
	@sh runtests.sh sh ${TESTS}
