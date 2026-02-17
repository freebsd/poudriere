OVERLAYS="omnibus"
# Not setting TESTPORT until after the bulk run as bulk checks use it.
PORT_TO_TEST="misc/foo"
LISTPORTS="${PORT_TO_TEST}"
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

	EXPECTED_QUEUED="ports-mgmt/pkg ${PORT_TO_TEST}:listed"
	EXPECTED_LISTED="${PORT_TO_TEST}"
	EXPECTED_TOBUILD="${EXPECTED_QUEUED}"
	EXPECTED_BUILT=

	# First build everything with bulk.
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
	assert 0 "$?"
	echo "------" | tee /dev/stderr

	# Remember and check packages were made.
	allpackages="$(/bin/ls ${PACKAGES:?}/All/)"
	assert_true [ -e "${PACKAGES:?}/All/pkg-"*".${PKG_EXT:?}" ]
	assert_true [ -e "${PACKAGES:?}/All/foo"*".${PKG_EXT:?}" ]
	expected_mtime="$(stat -f%m "${PACKAGES:?}/All/foo"*".${PKG_EXT:?}")"

	# Now run through testport and make sure everything remains.

	# Set TESTPORT so assert_bulk_build_results knows we did testport.
	TESTPORT="${PORT_TO_TEST}"
	EXPECTED_BUILT=
	# Need to remove pkg from the expected queued, it's already built.
	# But the testport itself _should_ be queued.
	EXPECTED_QUEUED="${TESTPORT}:listed"
	EXPECTED_LISTED="${TESTPORT}"
	EXPECTED_TOBUILD="${EXPECTED_QUEUED}"
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
	assert_true [ -e "${PACKAGES:?}/All/pkg-"*".${PKG_EXT:?}" ]
	# Package should have been restored.
	assert_true [ -e "${PACKAGES:?}/All/foo"*".${PKG_EXT:?}" ]
	actual_mtime="$(stat -f%m "${PACKAGES:?}/All/foo"*".${PKG_EXT:?}")"
	assert "${expected_mtime}" "${actual_mtime}" "foo package should be untouched"
	nowpackages="$(/bin/ls ${PACKAGES:?}/All/)"
	assert 0 "$?"
	assert "${allpackages}" "${nowpackages}"
done
