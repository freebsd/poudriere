# This test is not doing much but running through a basic distclean.
. ./common.bulk.sh

while slocked locktmp "test-distclean" 5; do
	TESTFILE="$(TMPDIR="${DISTFILES_CACHE:?}" mktemp -t distclean-smoke)"
	touch "${TESTFILE:?}"

	do_distclean -n -a
	assert 0 "$?" "distclean should pass"

	# We told it to not delete anything
	ret=0
	[ -e "${TESTFILE:?}" ] || ret="$?"
	rm -f "${TESTFILE:?}"
	assert 0 "$?" "[ -e ${TESTFILE:?} ]"

	rm -f "${TESTFILE:?}"
done
