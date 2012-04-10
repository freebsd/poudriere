#!/bin/sh

LC_ALL=C
unset SHELL
unset TERM

usage() {
	echo "Usage: poudriere command [options]

Commands:
    bulk        -- generate packages for given ports
    cron        -- run poudriere from the crontab
    help        -- show usage informations
    jail        -- manage the jails used by poudriere
    ports       -- create, update or delete the portstrees used by poudriere
    queue       -- queue a build request (through cron)
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
		exec /bin/sh ${POUDRIEREPREFIX}/jail.sh $@
		;;
	testport)
		exec /bin/sh ${POUDRIEREPREFIX}/test_ports.sh $@
		;;
	bulk)
		exec /bin/sh ${POUDRIEREPREFIX}/bulk.sh $@
		;;
	ports)
		exec /bin/sh ${POUDRIEREPREFIX}/ports.sh $@
		;;
	queue)
		exec /bin/sh ${POUDRIEREPREFIX}/queue.sh $@
		;;
	cron)
		exec /bin/sh ${POUDRIEREPREFIX}/cron.sh
		;;
	help)
		usage
		;;
	*)
		echo "Unknown command ${CMD}"
		usage
		;;
esac
