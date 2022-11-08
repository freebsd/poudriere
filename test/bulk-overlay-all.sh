ALL=1
OVERLAYS="overlay omnibus"
. common.bulk.sh

do_bulk -n -a
assert 0 $? "Bulk should pass"

# Assert that we found the right misc/foo
ret=0
hash_get originspec-pkgname "misc/foo" pkgname || ret=$?
assert 0 "${ret}" "Cannot find pkgname for misc/foo"
assert "foo-OVERLAY-20161010" "${pkgname}" "misc/foo didn't find the overlay version"

EXPECTED_IGNORED="misc/foo-FLAVORS-unsorted@IGNORED misc/foo-FLAVORS-unsorted@DEPIGNORED misc/foo-dep-FLAVORS-unsorted@DEPIGNORED misc/foo-dep-FLAVORS-unsorted@IGNORED misc/foo@IGNORED_OVERLAY ports-mgmt/poudriere-devel-IGNORED ports-mgmt/poudriere-devel-IGNORED-and-skipped misc/foop-IGNORED misc/foo-all-IGNORED@DEFAULT misc/foo-all-IGNORED@FLAV misc/foo-default-IGNORED@DEFAULT misc/foo-all-DEPIGNORED@FLAV"
EXPECTED_SKIPPED="ports-mgmt/poudriere-devel-dep-IGNORED ports-mgmt/poudriere-devel-dep2-IGNORED misc/foo-all-DEPIGNORED@DEFAULT misc/foo-default-DEPIGNORED@DEFAULT"
EXPECTED_QUEUED="converters/libiconv devel/ccache devel/gettext devel/gettext-runtime devel/gettext-tools devel/libffi devel/libtextstyle devel/pkgconf devel/readline lang/perl5.30 lang/python lang/python2 lang/python27 lang/python3 lang/python37 misc/foo misc/foo-FLAVORS-unsorted misc/foo-FLAVORS-unsorted@FLAV misc/foo-default-DEPIGNORED@FLAV misc/foo-default-IGNORED@FLAV misc/foo-dep-FLAVORS-unsorted misc/foo-dep-FLAVORS-unsorted@FLAV misc/foo@FLAV misc/freebsd-release-manifests misc/freebsd-release-manifests@BAR misc/freebsd-release-manifests@FOO ports-mgmt/pkg ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-dep-DEFAULT ports-mgmt/poudriere-devel-dep-FOO ports-mgmt/yyyy ports-mgmt/zzzz print/indexinfo security/openssl"
EXPECTED_LISTED="converters/libiconv devel/ccache devel/gettext devel/gettext-runtime devel/gettext-tools devel/libffi devel/libtextstyle devel/pkgconf devel/readline lang/perl5.30 lang/python lang/python2 lang/python27 lang/python3 lang/python37 misc/foo misc/foo-FLAVORS-unsorted misc/foo-FLAVORS-unsorted@DEPIGNORED misc/foo-FLAVORS-unsorted@FLAV misc/foo-FLAVORS-unsorted@IGNORED misc/foo-all-DEPIGNORED misc/foo-all-DEPIGNORED@FLAV misc/foo-all-IGNORED misc/foo-all-IGNORED@FLAV misc/foo-default-DEPIGNORED misc/foo-default-DEPIGNORED@FLAV misc/foo-default-IGNORED misc/foo-default-IGNORED@FLAV misc/foo-dep-FLAVORS-unsorted misc/foo-dep-FLAVORS-unsorted@DEPIGNORED misc/foo-dep-FLAVORS-unsorted@FLAV misc/foo-dep-FLAVORS-unsorted@IGNORED misc/foo@FLAV misc/foo@IGNORED_OVERLAY misc/foop-IGNORED misc/freebsd-release-manifests misc/freebsd-release-manifests@BAR misc/freebsd-release-manifests@FOO ports-mgmt/pkg ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-IGNORED ports-mgmt/poudriere-devel-IGNORED-and-skipped ports-mgmt/poudriere-devel-dep-DEFAULT ports-mgmt/poudriere-devel-dep-FOO ports-mgmt/poudriere-devel-dep-IGNORED ports-mgmt/poudriere-devel-dep2-IGNORED ports-mgmt/yyyy ports-mgmt/zzzz print/indexinfo security/openssl"

assert_bulk_queue_and_stats
