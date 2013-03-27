#!/bin/sh

LC_ALL=C
unset SHELL
SAVED_TERM=$TERM
unset TERM
POUDRIERE_VERSION="2.4.1"

usage() {
	echo "Usage: poudriere command [options]

Commands:
    bulk        -- generate packages for given ports
    cron        -- run poudriere from the crontab (DEPRECATED)
    distclean   -- clean old distfiles
    help        -- show usage
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
		exec env -i PATH=${PATH} POUDRIERE_VERSION="${POUDRIERE_VERSION}" /bin/sh ${POUDRIEREPREFIX}/jail.sh $@
		;;
	testport)
		exec env -i PATH=${PATH} POUDRIERE_VERSION="${POUDRIERE_VERSION}" SAVED_TERM=${SAVED_TERM} /bin/sh ${POUDRIEREPREFIX}/testport.sh $@
		;;
	bulk)
		exec env -i PATH=${PATH} POUDRIERE_VERSION="${POUDRIERE_VERSION}" /bin/sh ${POUDRIEREPREFIX}/bulk.sh $@
		;;
	distclean)
		exec env -i PATH=${PATH} POUDRIERE_VERSION="${POUDRIERE_VERSION}" /bin/sh ${POUDRIEREPREFIX}/distclean.sh $@
		;;
	ports)
		exec env -i PATH=${PATH} POUDRIERE_VERSION="${POUDRIERE_VERSION}" /bin/sh ${POUDRIEREPREFIX}/ports.sh $@
		;;
	queue)
		exec env -i PATH=${PATH} POUDRIERE_VERSION="${POUDRIERE_VERSION}" /bin/sh ${POUDRIEREPREFIX}/queue.sh $@
		;;
	cron)
		exec env -i PATH=${PATH} POUDRIERE_VERSION="${POUDRIERE_VERSION}" /bin/sh ${POUDRIEREPREFIX}/cron.sh
		;;
	options)
		exec env -i TERM=${SAVED_TERM} PATH=${PATH} POUDRIERE_VERSION="${POUDRIERE_VERSION}" /bin/sh ${POUDRIEREPREFIX}/options.sh $@
		;;
	help)
		usage
		;;
	version)
		echo "${POUDRIERE_VERSION}"
		;;
	*)
		echo "Unknown command ${CMD}"
		usage
		;;
esac
