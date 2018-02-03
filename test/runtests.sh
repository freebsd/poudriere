#! /bin/sh

export PATH=..:${PATH}

if [ -f "./$1" ]; then
	echo "Usage: $0: sh test" >&2
	exit 1
fi
export SH="$1"
: ${TIMEOUT:=30}
shift
TESTS="$@"

echo "Running in ${PWD}"

FAILED_TESTS=
for test in ${TESTS}; do
	if [ -n "${TEST_FILTER}" ]; then
		case "${test}" in
			${TEST_FILTER}|${TEST_FILTER}.sh) ;;
			*) continue ;;
		esac
	fi
	status=0
	echo -n "Running ${SH} ${test} ... "
	${SH} runtest.sh ${test} > ${test}.stdout.log 2> ${test}.stderr.log ||
	    status=$?
	if [ ${status} -ne 0 ]; then
		if [ ${status} -eq 124 ]; then
			status="124 (timeout)"
		fi
		if grep -q SKIP ${test}.stderr.log; then
			echo "skipped: $(cat ${test}.stderr.log)"
		else
			echo "failed: ${status}"
			FAILED_TESTS="${FAILED_TESTS}${FAILED_TESTS:+ }${test}"
		fi
	else
		echo "pass"
	fi
done

if [ -n "${FAILED_TESTS}" ]; then
	echo "Failed tests:"
	for test in ${FAILED_TESTS}; do
		cat ${test}.stderr.log | sed -e "s,^,${test}: ,"
	done
	exit 1
fi
exit 0
