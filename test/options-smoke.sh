# This test is not doing much but running through a basic options.
. ./common.bulk.sh

do_options -s -n ports-mgmt/pkg
assert 0 "$?" "options should pass"
