# This test is not doing much but running through a basic distclean.
. ./common.bulk.sh

while slocked locktmp "test-${SCRIPTNAME}" 5; do
#until slock_acquire "test-${SCRIPTNAME}" 5; do
#	:
#done
	touch "${DISTFILES_CACHE:?}/junk"

	do_distclean -n -a
	assert 0 "$?" "distclean should pass"

	# We told it to not delete anything
	assert_ret 0 [ -e "${DISTFILES_CACHE}/junk" ]

	rm -f "${DISTFILES_CACHE:?}/junk"
done
#slock_release "test-${SCRIPTNAME}"
