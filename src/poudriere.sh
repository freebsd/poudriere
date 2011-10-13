#!/bin/sh

LC_ALL=C
SHELL=/bin/sh; export SHELL

usage() {
	echo "Usage: poudriere command [options]

Commands:
    bulk        -- generate packages for given ports
    genpkg      -- generate package for a given port
    jail        -- manage the jails used by poudriere
    ports       -- create, update or delete the portstrees used by poudriere
    testport    -- launch a test on a given port"
	exit 1
}

[ $# -lt 1 ] && usage

POUDRIEREPATH=`realpath $0`
POUDRIEREPREFIX=${POUDRIEREPATH%\/bin/*}
POUDRIEREPREFIX=${POUDRIEREPREFIX}/share/poudriere

CMD=$1
shift

case ${CMD} in
	jail|jails)
		/bin/sh ${POUDRIEREPREFIX}/jail.sh $@
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
	ports)
		/bin/sh ${POUDRIEREPREFIX}/ports.sh $@
		;;
	*)
		echo "Unknown command ${CMD}"
		usage
		;;
esac
