OVERLAYS=omnibus
. ./common.bulk.sh

do_distclean -n misc/foo
assert 0 "$?" "distclean should pass"
