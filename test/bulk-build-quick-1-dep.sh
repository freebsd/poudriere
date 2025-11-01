LISTPORTS="ports-mgmt/pkg misc/foo@default"
OVERLAYS="omnibus"
. ./common.bulk.sh

set_test_contexts - '' '' <<-EOF
+queue-setup-tests PKG_NO_VERSION_FOR_DEPS no yes
+queue-running-tests JFLAG 1:1 4:4
EOF
while get_test_context; do
	set_poudriere_conf <<-EOF
	PKG_NO_VERSION_FOR_DEPS=${PKG_NO_VERSION_FOR_DEPS:?}
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
done
