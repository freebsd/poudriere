LISTPORTS="ports-mgmt/poudriere-devel-bad-dep_args"
OVERLAYS="ports-dep-args"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 1 $? "Invalid DEPENDS_ARGS should be detected"

# Nothing should be queued
[ -f "${log}/.poudriere.ports.queued" ] && \
    [ -s "${log}/.poudriere.ports.queued" ]
assert 1 $? "Nothing should be queued for this bad DEPENDS_ARGS"
