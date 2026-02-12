FLAVOR_DEFAULT_ALL=no
FLAVOR_ALL=all
LISTPORTS="\
	ports-mgmt/poudriere-devel \
	misc/freebsd-release-manifests@${FLAVOR_ALL} \
	misc/foo@${FLAVOR_ALL} \
	misc/foo-FLAVORS-unsorted@${FLAVOR_ALL} \
"
JFLAG=4
OVERLAYS="omnibus"
. ./common.bulk.sh

do_pkgclean -y -A
assert 0 "$?" "Pkgclean should pass"

EXPECTED_IGNORED="misc/foo-FLAVORS-unsorted@ignored misc/foo-FLAVORS-unsorted@depignored misc/foo@ignored misc/foo-dep-FLAVORS-unsorted@depignored"
EXPECTED_TOBUILD="misc/foo@default misc/foo-FLAVORS-unsorted@default misc/foo-FLAVORS-unsorted@flav misc/foo@flav misc/freebsd-release-manifests@default misc/freebsd-release-manifests@bar misc/freebsd-release-manifests@foo ports-mgmt/pkg ports-mgmt/poudriere-devel misc/foo-dep-FLAVORS-unsorted@default misc/foo-dep-FLAVORS-unsorted@flav"
EXPECTED_QUEUED="${EXPECTED_TOBUILD} ${EXPECTED_IGNORED}"
EXPECTED_LISTED="${LISTPORTS}"

# Cause foo's builder to crash rather than port failure.
set_make_conf <<-EOF
misc_foo_UNSET=	FAILURE
EOF

set_poudriere_conf <<-EOF
FP_BUILD_PKG_EXIT_PKGNAMES="foo"
EOF

# Remove misc/foo@* and misc/freebsd-release-manifests@foo
EXPECTED_BUILT="misc/foo-FLAVORS-unsorted@default misc/foo-FLAVORS-unsorted@flav misc/freebsd-release-manifests@default misc/freebsd-release-manifests@bar ports-mgmt/pkg ports-mgmt/poudriere-devel misc/foo-dep-FLAVORS-unsorted@default misc/foo-dep-FLAVORS-unsorted@flav misc/foo@flav misc/foo@default:build_port_done"
EXPECTED_FAILED="misc/foo@default:build_port_done"
EXPECTED_CRASHED="foo-20161010"
EXPECTED_SKIPPED="misc/freebsd-release-manifests@foo:foo-20161010"

do_bulk -c "${LISTPORTS}"
assert 70 "$?" "Bulk should exit EX_SOFTWARE"

# Don't check stats as they are going to be wrong on a success+crash.
# assert_bulk_queue_and_stats
assert_bulk_build_results
