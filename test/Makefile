TESTS=\
	cache.sh \
	encode_args.sh \
	hash_basic.sh \
	list.sh \
	locks.sh \
	locks_critical_section.sh \
	locks_critical_section_nested.sh \
	port_var_fetch.sh \
	read_file.sh \
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
	bulk-flavor-nonexistent.sh \
	bulk-flavor-specific-dep-and-default-listed.sh \
	bulk-flavor-specific-dep-and-default-shorthand-listed.sh \
	bulk-flavor-specific-dep-and-main-listed_default_all_off.sh \
	bulk-flavor-specific-dep-and-main-listed_default_all_off_w_@all.sh \
	bulk-flavor-specific-dep-and-main-listed_default_all_on.sh \
	bulk-flavor-specific-dep-and-multi-listed.sh \
	bulk-flavor-specific-dep-and-multi-no-main-listed.sh \
	bulk-flavor-specific-dep-and-specific-listed.sh \
	bulk-flavor-specific-dep-and-specific-listed-nonexistent.sh \
	bulk-flavor-specific-dep-nonexistent.sh \
	bulk-flavor-specific-dep.sh \
	bulk-flavor-metadata-queue-ordering.sh \
	bulk-flavor-metadata-queue-ordering-multi-pass.sh \
	bulk-flavor-all.sh

all: check check-stock

check: .PHONY
	@echo "Running tests against modified sh"
	@sh runtests.sh sh ${TESTS}

check-stock: .PHONY
	@echo "Running tests against stock /bin/sh"
	@sh runtests.sh /bin/sh ${TESTS}
