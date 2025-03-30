FLAVOR_ALL=all
FLAVOR_DEFAULT=-
LISTPORTS="misc/freebsd-release-manifests@${FLAVOR_ALL}"
LISTPORTS_MOVED="misc/freebsd-release-manifests-OLD-MOVED@${FLAVOR_ALL}"
OVERLAYS="omnibus"
. ./common.bulk.sh

: ${ASSERT_CONTINUE:=0}
set_test_contexts - '' '' <<-EOF
BLACKLISTED_FLAVOR "" ${FLAVOR_ALL} ${FLAVOR_DEFAULT} default foo
EOF

do_bulk ports-mgmt/pkg
assert 0 "$?" "bulk for pkg should pass"

while get_test_context; do
	set_blacklist <<-EOF
	misc/freebsd-release-manifests${BLACKLISTED_FLAVOR:+@${BLACKLISTED_FLAVOR}}
	EOF

	do_bulk -n -C ${LISTPORTS_MOVED}
	assert 0 $? "Bulk should pass"

	EXPECTED_LISTED="${LISTPORTS}"
	EXPECTED_QUEUED="${LISTPORTS}"
	EXPECTED_TOBUILD=
	case "${BLACKLISTED_FLAVOR?}" in
	""|"${FLAVOR_ALL}")
		# Entire port blacklisted
		EXPECTED_IGNORED="misc/freebsd-release-manifests@${FLAVOR_ALL}:Blacklisted"
		;;
	default|"${FLAVOR_DEFAULT}")
		EXPECTED_TOBUILD="misc/freebsd-release-manifests@foo:listed misc/foo misc/freebsd-release-manifests@bar:listed"
		EXPECTED_IGNORED="misc/freebsd-release-manifests@${BLACKLISTED_FLAVOR:?}:Blacklisted"
		EXPECTED_QUEUED="${EXPECTED_QUEUED} misc/foo"
		;;
	foo)
		EXPECTED_TOBUILD="misc/freebsd-release-manifests@default:listed misc/freebsd-release-manifests@bar:listed"
		EXPECTED_IGNORED="misc/freebsd-release-manifests@${BLACKLISTED_FLAVOR:?}:Blacklisted"
		;;
	esac

	assert_bulk_queue_and_stats
	assert_bulk_dry_run
done
