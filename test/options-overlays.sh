OVERLAYS=omnibus
. ./common.bulk.sh

do_options -s -n misc/foo
assert 0 "$?" "options should pass"
