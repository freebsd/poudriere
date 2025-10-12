OVERLAYS=""
TESTPORT="ports-mgmt/pkg"
LISTPORTS="${TESTPORT}"
. ./common.bulk.sh

set_test_contexts - '' '' <<-EOF
PKG_NO_VERSION_FOR_DEPS no yes
EOF
while get_test_context; do
	set_poudriere_conf <<-EOF
	PKG_NO_VERSION_FOR_DEPS=${PKG_NO_VERSION_FOR_DEPS:?}
	EOF

	# testport will keep old packages so we need to clean out everything
	# before doing the first run to ensure it all builds.
	do_pkgclean -y -A
	assert 0 $? "Pkgclean should pass"
	echo "-----" | tee /dev/stderr

	EXPECTED_QUEUED="${TESTPORT}:listed"
	EXPECTED_LISTED="${TESTPORT}"
	EXPECTED_TOBUILD="${EXPECTED_QUEUED}"
	EXPECTED_BUILT=
	do_testport -n ${TESTPORT}
	assert 0 "$?" "testport dry-run should pass"
	assert_bulk_queue_and_stats
	assert_bulk_build_results
	echo "-----" | tee /dev/stderr

	EXPECTED_BUILT="${EXPECTED_TOBUILD}"
	EXPECTED_FAILED=""
	do_testport ${TESTPORT}
	assert 0 "$?" "testport should pass"
	assert_bulk_queue_and_stats
	assert_bulk_build_results
	echo "-----" | tee /dev/stderr
done
