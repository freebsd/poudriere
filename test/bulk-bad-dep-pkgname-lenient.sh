LISTPORTS="ports-mgmt/yyyy"
OVERLAYS="overlay omnibus"
. ./common.bulk.sh

set_poudriere_conf <<-EOF
BAD_PKGNAME_DEPS_ARE_FATAL=yes
EOF

# With -d (STRICT_DEPS=0), a "fatal" bad PKGNAME dependency only ignores
# the affected port instead of aborting the whole build.
do_bulk -c -n -d ${LISTPORTS}
assert 0 $? "Bulk -d should pass: bad PKGNAME dep should only ignore the port"

EXPECTED_IGNORED="${LISTPORTS}"
# misc/foo@flav is only needed by the ignored port, so it is not queued.
EXPECTED_TOBUILD="ports-mgmt/pkg"
EXPECTED_QUEUED="${EXPECTED_TOBUILD} ${LISTPORTS}"
EXPECTED_LISTED="${LISTPORTS}"

assert_bulk_queue_and_stats
assert_bulk_dry_run

# -D (STRICT_DEPS=1) keeps it fatal.
do_bulk -c -n -D ${LISTPORTS}
assert 1 $? "Bulk -D should fail"
