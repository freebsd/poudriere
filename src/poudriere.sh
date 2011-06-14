#!/bin/sh

LC_ALL=C
SHELL=/bin/sh

usage() {
	echo "poudriere command [options]"
cat <<EOF

Commands:
    createjail  -- create a new jail to test ports
    removejail  -- remove the jail whose name is given to the -j option
    startjail   -- start the jail whose name is given to the -j option
    stopjail    -- stop the jail whose name is given to the -j option
    testport    -- launch a test on a given port
    genpkg      -- generate package for a given port
    bulk        -- generate packages for given ports
    lsjail      -- list jails created and used by poudriere
    ports       -- create, update or delete the portstrees used by poudriere
EOF
	exit 1
}

POUDRIEREPATH=`realpath $0`
POUDRIEREPREFIX=${POUDRIEREPATH%\/bin/*}
[ $# -lt 1 ] && usage

case $1 in
	createjail)
		shift
		/bin/sh ${POUDRIEREPREFIX}/share/poudriere/create_jail.sh $@
	;;
	removejail)
		shift
		/bin/sh ${POUDRIEREPREFIX}/share/poudriere/remove_jail.sh $@
	;;
	startjail)
		shift
		/bin/sh ${POUDRIEREPREFIX}/share/poudriere/start_jail.sh $@
	;;
	stopjail)
		shift
		/bin/sh ${POUDRIEREPREFIX}/share/poudriere/stop_jail.sh $@
	;;
	testport)
		shift
		/bin/sh ${POUDRIEREPREFIX}/share/poudriere/test_ports.sh $@
	;;
	genpkg)
		shift
		/bin/sh ${POUDRIEREPREFIX}/share/poudriere/gen_package.sh $@
	;;
	bulk)
		shift
		/bin/sh ${POUDRIEREPREFIX}/share/poudriere/bulk.sh $@
	;;
	lsjail|lsjails)
		shift
		/bin/sh ${POUDRIEREPREFIX}/share/poudriere/list_jails.sh $@
	;;
	ports)
		shift
		/bin/sh ${POUDRIEREPREFIX}/share/poudriere/ports.sh $@
	;;
	*)
		echo "unknown command $1"
		usage
	;;
esac
