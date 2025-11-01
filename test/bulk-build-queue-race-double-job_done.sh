LISTPORTS="ports-mgmt/pkg misc/foo@default"
OVERLAYS="omnibus"
. ./common.bulk.sh

set_test_contexts - '' '' <<-EOF
+queue-running-tests JFLAG 1:1 4:4
# A race existed with JFLAG="1:1"; FP_BUILD_QUEUE_POST_READ="1"; BUILD_QUEUE_TIMEOUT="0";
# +queue-running-tests FP_BUILD_QUEUE_RUNNER_ENTER_SLEEP "" 3 7
# +queue-running-tests FP_BUILD_QUEUE_RUNNER_EXIT_SLEEP "" 3 7
# +queue-running-tests FP_BUILD_QUEUE_POST_READ "" 1 3 7
+queue-running-tests FP_BUILD_QUEUE_POST_READ "" 1
+queue-running-tests BUILD_QUEUE_TIMEOUT 0 30
EOF
while get_test_context; do
	set_poudriere_conf <<-EOF
	${FP_BUILD_QUEUE_POST_READ:+FP_BUILD_QUEUE_POST_READ="${FP_BUILD_QUEUE_POST_READ}"}
	${BUILD_QUEUE_TIMEOUT:+BUILD_QUEUE_TIMEOUT="${BUILD_QUEUE_TIMEOUT}"}
	${FP_BUILD_QUEUE_RUNNER_ENTER_SLEEP:+FP_BUILD_QUEUE_RUNNER_ENTER_SLEEP="${FP_BUILD_QUEUE_RUNNER_ENTER_SLEEP}"}
	${FP_BUILD_QUEUE_RUNNER_EXIT_SLEEP:+FP_BUILD_QUEUE_RUNNER_EXIT_SLEEP="${FP_BUILD_QUEUE_RUNNER_EXIT_SLEEP}"}
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
