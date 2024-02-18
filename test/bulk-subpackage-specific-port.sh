LISTPORTS="ports-mgmt/subpkgtest"
OVERLAYS="subpkg"
. common.bulk.sh

do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

#EXPECTED_QUEUED="ports-mgmt/subpkgtest~cmd2 ports-mgmt/subpkgtest~data1 ports-mgmt/subpkgtest~data2 ports-mgmt/subpkgtest~docs ports-mgmt/subpkgtest~examples sysutils/pstree ports-mgmt/pkg"
EXPECTED_QUEUED="ports-mgmt/subpkgtest sysutils/pstree ports-mgmt/pkg"
#EXPECTED_LISTED="ports-mgmt/subpkgtest~cmd2 ports-mgmt/subpkgtest~data1 ports-mgmt/subpkgtest~data2 ports-mgmt/subpkgtest~docs ports-mgmt/subpkgtest~examples"
EXPECTED_LISTED="ports-mgmt/subpkgtest"

assert_bulk_queue_and_stats
assert_bulk_dry_run
