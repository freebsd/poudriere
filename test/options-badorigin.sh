# This test is not doing much but running through a basic options.
. ./common.bulk.sh

do_options -s -n nonexistent/origin
assert 1 "$?" "options should fail"
