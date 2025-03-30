ALL=1
OVERLAYS="omnibus"
set -e
. ./common.bulk.sh
set +e

do_bulk -c -n -a
assert 0 $? "Bulk should pass"

EXPECTED_IGNORED="misc/foo-FLAVORS-unsorted@ignored misc/foo-FLAVORS-unsorted@depignored misc/foo-dep-FLAVORS-unsorted@depignored misc/foo-dep-FLAVORS-unsorted@ignored misc/foo@ignored ports-mgmt/poudriere-devel-IGNORED ports-mgmt/poudriere-devel-IGNORED-and-skipped misc/foop-IGNORED misc/foo-all-IGNORED@default misc/foo-all-IGNORED@flav misc/foo-default-IGNORED@default misc/foo-all-DEPIGNORED@flav misc/foo-flavor-double-DEPIGNORED@depignored"
EXPECTED_SKIPPED="ports-mgmt/poudriere-devel-dep-IGNORED ports-mgmt/poudriere-devel-dep2-IGNORED misc/foo-all-DEPIGNORED@default misc/foo-default-DEPIGNORED@default"
EXPECTED_TOBUILD="converters/libiconv devel/ccache devel/gettext devel/gettext-runtime devel/gettext-tools devel/libffi devel/libtextstyle devel/pkgconf devel/readline lang/perl5.36 lang/python lang/python2 lang/python27 lang/python3 lang/python39 misc/foo@default misc/foo-FLAVORS-unsorted@default misc/foo-FLAVORS-unsorted@flav misc/foo-default-DEPIGNORED@flav misc/foo-default-IGNORED@flav misc/foo-dep-FLAVORS-unsorted@default misc/foo-dep-FLAVORS-unsorted@flav misc/foo@flav misc/freebsd-release-manifests@default misc/freebsd-release-manifests@bar misc/freebsd-release-manifests@foo ports-mgmt/pkg ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-dep-DEFAULT ports-mgmt/poudriere-devel-dep-FOO ports-mgmt/yyyy ports-mgmt/zzzz print/indexinfo security/openssl misc/foo-flavor-double-DEPIGNORED@default"
# With -a this is simply everything
EXPECTED_QUEUED="${EXPECTED_TOBUILD} ${EXPECTED_IGNORED} ${EXPECTED_SKIPPED}"
EXPECTED_LISTED="converters/libiconv devel/ccache devel/gettext devel/gettext-runtime devel/gettext-tools devel/libffi devel/libtextstyle devel/pkgconf devel/readline lang/perl5.36 lang/python lang/python2 lang/python27 lang/python3 lang/python39 misc/foo@default misc/foo-FLAVORS-unsorted@default misc/foo-FLAVORS-unsorted@depignored misc/foo-FLAVORS-unsorted@flav misc/foo-FLAVORS-unsorted@ignored misc/foo-all-DEPIGNORED@default misc/foo-all-DEPIGNORED@flav misc/foo-all-IGNORED misc/foo-all-IGNORED@flav misc/foo-default-DEPIGNORED@default misc/foo-default-DEPIGNORED@flav misc/foo-default-IGNORED@default misc/foo-default-IGNORED@flav misc/foo-dep-FLAVORS-unsorted@default misc/foo-dep-FLAVORS-unsorted@depignored misc/foo-dep-FLAVORS-unsorted@flav misc/foo-dep-FLAVORS-unsorted@ignored misc/foo@flav misc/foo@ignored misc/foop-IGNORED misc/freebsd-release-manifests@default misc/freebsd-release-manifests@bar misc/freebsd-release-manifests@foo ports-mgmt/pkg ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-IGNORED ports-mgmt/poudriere-devel-IGNORED-and-skipped ports-mgmt/poudriere-devel-dep-DEFAULT ports-mgmt/poudriere-devel-dep-FOO ports-mgmt/poudriere-devel-dep-IGNORED ports-mgmt/poudriere-devel-dep2-IGNORED ports-mgmt/yyyy ports-mgmt/zzzz print/indexinfo security/openssl misc/foo-flavor-double-DEPIGNORED@default misc/foo-flavor-double-DEPIGNORED@depignored"

assert_bulk_queue_and_stats
assert_bulk_dry_run
