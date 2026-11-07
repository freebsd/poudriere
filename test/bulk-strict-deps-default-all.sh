ALL=1
OVERLAYS="strict-deps"
set -e
. ./common.bulk.sh
set +e

# With -a, STRICT_DEPS defaults to 0 (lenient): a dependency on a
# nonexistent origin, or on a FLAVOR that does not exist for an otherwise
# valid origin, should only ignore the affected port instead of aborting
# the whole build.
do_bulk -c -n -a
assert 0 $? "Bulk -a should not fail by default (STRICT_DEPS defaults to 0)"

EXPECTED_IGNORED="misc/foo-dep-invalid-flavor misc/foo-dep-invalid-flavor-versioned"
EXPECTED_SKIPPED=
EXPECTED_TOBUILD="converters/libiconv devel/ccache devel/gettext devel/gettext-runtime devel/gettext-tools devel/libffi devel/libtextstyle devel/pkgconf devel/readline lang/perl5.36 lang/python lang/python2 lang/python27 lang/python3 lang/python39 ports-mgmt/pkg print/indexinfo security/openssl misc/bar@default misc/bar@flav"
EXPECTED_QUEUED="${EXPECTED_TOBUILD} ${EXPECTED_IGNORED} ${EXPECTED_SKIPPED}"
EXPECTED_LISTED="${EXPECTED_QUEUED}"

assert_bulk_queue_and_stats
assert_bulk_dry_run

# -D forces STRICT_DEPS=1 even with -a: the same tree must now fail.
do_bulk -c -n -D -a
assert 1 $? "Bulk -a -D should fail due to nonexistent origin/invalid FLAVOR dependency"
