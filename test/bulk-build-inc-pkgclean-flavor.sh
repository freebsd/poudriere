LISTPORTS="ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-dep-FOO misc/freebsd-release-manifests@foo"
OVERLAYS="omnibus"
. ./common.bulk.sh

do_pkgclean -y -A
assert 0 "$?" "Pkgclean should pass"

EXPECTED_IGNORED=""
EXPECTED_SKIPPED=
EXPECTED_TOBUILD="ports-mgmt/poudriere-devel-dep-FOO misc/freebsd-release-manifests@default ports-mgmt/pkg ports-mgmt/poudriere-devel misc/freebsd-release-manifests@foo misc/foo@default:misc/freebsd-release-manifests@foo"
EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
EXPECTED_LISTED="${LISTPORTS}"
EXPECTED_BUILT=
do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_dry_run
echo "------" | tee /dev/stderr

EXPECTED_BUILT="${EXPECTED_TOBUILD}"
do_bulk -c ${LISTPORTS}
assert 0 $? "Bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
allpackages="$(/bin/ls ${PACKAGES:?}/All/)"
assert 0 "$?"
echo "------" | tee /dev/stderr

assert_true [ -e "${PACKAGES:?}/All/freebsd-release-manifests-FOO-20161010.${PKG_EXT:?}" ]
assert_true [ -e "${PACKAGES:?}/All/freebsd-release-manifests-20161010.${PKG_EXT:?}" ]
do_pkgclean -y -C misc/freebsd-release-manifests@foo
assert 0 "$?" "Pkgclean should pass"
nowpackages="$(/bin/ls ${PACKAGES:?}/All/)"
assert 0 "$?"
assert_not "${allpackages}" "${nowpackages}"
assert_false [ -e "${PACKAGES:?}/All/freebsd-release-manifests-FOO-20161010.${PKG_EXT:?}" ]
assert_true [ -e "${PACKAGES:?}/All/freebsd-release-manifests-20161010.${PKG_EXT:?}" ]
EXPECTED_IGNORED=""
EXPECTED_SKIPPED=
EXPECTED_TOBUILD="misc/freebsd-release-manifests@foo"
case "${PKG_NO_VERSION_FOR_DEPS-}" in
yes) ;;
*)
	# Incremental build deletes rdeps when deps are missing.
	EXPECTED_TOBUILD="${EXPECTED_TOBUILD} ports-mgmt/poudriere-devel-dep-FOO"
	;;
esac
EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
EXPECTED_LISTED="${LISTPORTS}"
EXPECTED_BUILT="${EXPECTED_TOBUILD}"
do_bulk ${LISTPORTS}
assert 0 $? "Bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
nowpackages="$(/bin/ls ${PACKAGES:?}/All/)"
assert 0 "$?"
assert "${allpackages}" "${nowpackages}"
echo "------" | tee /dev/stderr
