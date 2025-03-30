# This test is not doing much but running through a basic distclean.
. ./common.bulk.sh

do_distclean -n nonexistent/origin
assert 1 "$?" "distclean should fail"
