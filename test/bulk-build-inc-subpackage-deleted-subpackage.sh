LISTPORTS="ports-mgmt/subpkgtest"
OVERLAYS="subpkg"
. common.bulk.sh

do_pkgclean -y -A
assert 0 "$?" "Pkgclean should pass"

EXPECTED_IGNORED=""
EXPECTED_SKIPPED=
EXPECTED_TOBUILD="ports-mgmt/subpkgtest ports-mgmt/pkg sysutils/pstree"
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

expected_pkgs=" \
port-test-0.0.2.${PKG_EXT:?} \
port-test-cmd2-0.0.2.${PKG_EXT:?} \
port-test-data1-0.0.2.${PKG_EXT:?} \
port-test-data2-0.0.2.${PKG_EXT:?} \
port-test-docs-0.0.2.${PKG_EXT:?} \
port-test-examples-0.0.2.${PKG_EXT:?} \
pstree-2.40_1.${PKG_EXT:?} \
"
for pkg in ${expected_pkgs}; do
	assert_true [ -e "${PACKAGES:?}/All/${pkg}" ]
done

# bulk-build-inc-subpackage.sh tests for no changes in a subsequent build.
# In this test we will now disable a subpackage and ensure everything is
# rebuilt.
set_make_conf <<-EOF
ports_mgmt_subpkgtest_UNSET=	EXAMPLES
EOF

EXPECTED_IGNORED=""
EXPECTED_SKIPPED=
EXPECTED_TOBUILD="ports-mgmt/subpkgtest"
EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
EXPECTED_LISTED="${LISTPORTS}"
EXPECTED_BUILT=
do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_dry_run
echo "------" | tee /dev/stderr

EXPECTED_BUILT="${EXPECTED_TOBUILD}"
do_bulk ${LISTPORTS}
assert 0 $? "Bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
nowpackages="$(/bin/ls ${PACKAGES:?}/All/)"
assert 0 "$?"
assert "${allpackages}" "${nowpackages}"
echo "------" | tee /dev/stderr
