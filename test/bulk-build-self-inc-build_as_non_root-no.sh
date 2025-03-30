LISTPORTS="ports-mgmt/poudriere-devel"
OVERLAYS="omnibus"
BUILD_AS_NON_ROOT=no
. ./common.bulk.sh

set_make_conf <<-EOF
ports-mgmt_poudriere-devel_SET=	CHECKNONROOT
EOF

EXPECTED_QUEUED="ports-mgmt/pkg misc/freebsd-release-manifests@default ports-mgmt/poudriere-devel"
EXPECTED_LISTED="ports-mgmt/poudriere-devel"
EXPECTED_TOBUILD="${EXPECTED_QUEUED}"
EXPECTED_BUILT="ports-mgmt/pkg misc/freebsd-release-manifests@default"
EXPECTED_FAILED="ports-mgmt/poudriere-devel:build"
do_bulk -t -c ${LISTPORTS}
assert 1 $? "Bulk should fail 1"
assert_bulk_queue_and_stats
assert_bulk_build_results
echo "-----" | tee /dev/stderr

do_pkgclean -y -C ports-mgmt/poudriere-devel
assert 0 "$?" "Pkgclean should pass"

set_make_conf <<-EOF
ports_mgmt_poudriere-devel_SET=	CHECKROOT
EOF

EXPECTED_QUEUED="ports-mgmt/poudriere-devel"
EXPECTED_LISTED="ports-mgmt/poudriere-devel"
EXPECTED_TOBUILD="${EXPECTED_QUEUED}"
EXPECTED_BUILT="${EXPECTED_TOBUILD}"
EXPECTED_FAILED=
do_bulk -t ${LISTPORTS}
assert 0 $? "Bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results

do_pkgclean_smoke
