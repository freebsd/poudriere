#!/bin/sh

LC_ALL=C
unset SHELL
SAVED_TERM=$TERM
unset TERM
VERSION="2.1.0"

usage() {
	echo "Usage: poudriere command [options]

Commands:
    bulk        -- generate packages for given ports
    cron        -- run poudriere from the crontab
    help        -- show usage informations
    jail        -- manage the jails used by poudriere
    ports       -- create, update or delete the portstrees used by poudriere
    options     -- Configure ports options
    queue       -- queue a build request (through cron)
    testport    -- launch a test on a given port
    version     -- show poudriere version"
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
		exec env -i PATH=${PATH} /bin/sh ${POUDRIEREPREFIX}/jail.sh $@
		;;
	testport)
		exec env -i PATH=${PATH} /bin/sh ${POUDRIEREPREFIX}/test_ports.sh $@
		;;
	bulk)
		exec env -i PATH=${PATH} /bin/sh ${POUDRIEREPREFIX}/bulk.sh $@
		;;
	ports)
		exec env -i PATH=${PATH} /bin/sh ${POUDRIEREPREFIX}/ports.sh $@
		;;
	queue)
		exec env -i PATH=${PATH} /bin/sh ${POUDRIEREPREFIX}/queue.sh $@
		;;
	cron)
		exec env -i PATH=${PATH} /bin/sh ${POUDRIEREPREFIX}/cron.sh
		;;
	pbi)
		exec env -i  PATH=${PATH} /bin/sh ${POUDRIEREPREFIX}/pbi.sh $@
		;;
	options)
		exec env -i TERM=${SAVED_TERM} PATH=${PATH} /bin/sh ${POUDRIEREPREFIX}/options.sh $@
		;;
	help)
		usage
		;;
	version)
		echo "${VERSION}"
		;;
	*)
		echo "Unknown command ${CMD}"
		usage
		;;
esac
