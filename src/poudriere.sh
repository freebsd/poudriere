#!/bin/sh

LC_ALL=C
SHELL=/bin/sh; export SHELL

usage() {
	echo "Usage: poudriere command [options]

Commands:
    createjail  -- create a new jail to test ports
    removejail  -- remove the jail whose name is given to the -j option
    startjail   -- start the jail whose name is given to the -j option
    stopjail    -- stop the jail whose name is given to the -j option
    testport    -- launch a test on a given port
    genpkg      -- generate package for a given port
    bulk        -- generate packages for given ports
    lsjail      -- list jails created and used by poudriere
    ports       -- create, update or delete the portstrees used by poudriere"

	exit 1
}

[ $# -lt 1 ] && usage

POUDRIEREPATH=`realpath $0`
POUDRIEREPREFIX=${POUDRIEREPATH%\/bin/*}
POUDRIEREPREFIX=${POUDRIEREPREFIX}/share/poudriere

CMD=$1
shift

case ${CMD} in
	createjail)
		/bin/sh ${POUDRIEREPREFIX}/create_jail.sh $@
		;;
	removejail)
		/bin/sh ${POUDRIEREPREFIX}/remove_jail.sh $@
		;;
	startjail)
		/bin/sh ${POUDRIEREPREFIX}/start_jail.sh $@
		;;
	stopjail)
		/bin/sh ${POUDRIEREPREFIX}/stop_jail.sh $@
		;;
	testport)
		/bin/sh ${POUDRIEREPREFIX}/test_ports.sh $@
		;;
	genpkg)
		/bin/sh ${POUDRIEREPREFIX}/gen_package.sh $@
		;;
	bulk)
		/bin/sh ${POUDRIEREPREFIX}/bulk.sh $@
		;;
	lsjail|lsjails)
		/bin/sh ${POUDRIEREPREFIX}/list_jails.sh $@
		;;
	ports)
		/bin/sh ${POUDRIEREPREFIX}/ports.sh $@
		;;
	*)
		echo "Unknown command ${CMD}"
		usage
		;;
esac
