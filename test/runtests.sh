#! /bin/sh

export PATH=..:${PATH}

SH="$1"
: ${TIMEOUT:=30}
shift
TESTS="$@"

FAILED_TESTS=
for test in ${TESTS}; do
	status=0
	echo -n "Running ${test} ... "
	${SH} runtest.sh ${test} > ${test}.stdout.log 2> ${test}.stderr.log
	if [ ${status} -ne 0 ]; then
		if [ ${status} -eq 124 ]; then
			status="124 (timeout)"
		fi
		echo "failed: ${status}"
		FAILED_TESTS="${FAILED_TESTS}${FAILED_TESTS:+ }${test}"
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
