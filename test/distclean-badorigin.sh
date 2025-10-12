# This test is not doing much but running through a basic distclean.
. ./common.bulk.sh

expect_error_on_stderr do_distclean -n nonexistent/origin
assert 1 "$?" "distclean should fail"
