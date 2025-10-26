LISTPORTS="ports-mgmt/pkg"
. ./common.bulk.sh

set_test_contexts - '' '' <<-EOF
PKG_NO_VERSION_FOR_DEPS no yes
EOF
while get_test_context; do
	set_poudriere_conf <<-EOF
	PKG_NO_VERSION_FOR_DEPS=${PKG_NO_VERSION_FOR_DEPS:?}
	PRIORITY_BOOST="pkg*"
	EOF

	EXPECTED_IGNORED=
	EXPECTED_INSPECTED=
	EXPECTED_SKIPPED=
	EXPECTED_TOBUILD="${LISTPORTS}"
	EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
	EXPECTED_LISTED="${LISTPORTS}"
	EXPECTED_BUILT=
	do_bulk -c -n ${LISTPORTS}
	assert 0 $? "Bulk should pass"
	assert_bulk_queue_and_stats
	assert_bulk_dry_run
	echo "------" | tee /dev/stderr

	EXPECTED_BUILT="${EXPECTED_TOBUILD}"
	do_bulk -c ${LISTPORTS}
	assert 0 $? "Bulk should pass"
	assert_bulk_queue_and_stats
	assert_bulk_build_results
	echo "------" | tee /dev/stderr

	_log_path log || err 99 "Unable to determine logdir"
	assert_true [ -e "${log:?}/.poudriere.pkg_deps_priority%" ]
	assert_true read pkgline < "${log:?}/.poudriere.pkg_deps_priority%"
	assert_case "99 build:pkg-*" "${pkgline}"
done
