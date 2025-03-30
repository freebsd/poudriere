LISTPORTS="ports-mgmt/yyyy"
OVERLAYS="overlay omnibus"
. ./common.bulk.sh

set_poudriere_conf <<-EOF
BAD_PKGNAME_DEPS_ARE_FATAL=no
EOF

do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_IGNORED=
EXPECTED_TOBUILD="${LISTPORTS} ports-mgmt/pkg misc/foo@flav"
EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
EXPECTED_LISTED="${LISTPORTS}"

assert_bulk_queue_and_stats
assert_bulk_dry_run

set_poudriere_conf <<-EOF
BAD_PKGNAME_DEPS_ARE_FATAL=yes
EOF

do_bulk -c -n ${LISTPORTS}
assert 1 $? "Bulk should fail"

EXPECTED_IGNORED=
EXPECTED_TOBUILD=
EXPECTED_QUEUED=
EXPECTED_LISTED=

assert_bulk_queue_and_stats
assert_bulk_dry_run
