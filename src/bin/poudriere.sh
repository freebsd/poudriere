#!/bin/sh

LC_ALL=C
unset SHELL
SAVED_TERM=$TERM
unset TERM
VERSION="3.0-pre"

usage() {
	echo "Usage: poudriere command [options]

Commands:
    bulk        -- generate packages for given ports
    distclean   -- clean old distfiles
    daemon      -- launch the poudriere daemon
    help        -- show usage
    jail        -- manage the jails used by poudriere
    ports       -- create, update or delete the portstrees used by poudriere
    options     -- Configure ports options
    queue       -- queue a build request
    testport    -- launch a test on a given port
    version     -- show poudriere version"
	exit 1
}

SETX=""
while getopts "x" FLAG; do
        case "${FLAG}" in
                x)
                        SETX="-x"
                        ;;
                *)
                        usage
                        ;;
        esac
done

shift $((OPTIND-1))

[ $# -lt 1 ] && usage

POUDRIEREPATH=`realpath $0`
POUDRIEREPREFIX=${POUDRIEREPATH%\/bin/*}
POUDRIEREPREFIX=${POUDRIEREPREFIX}/share/poudriere

CMD=$1
shift

case ${CMD} in
	jail|jails)
		exec env -i PATH=${PATH} VERSION="${VERSION}" /bin/sh ${SETX} ${POUDRIEREPREFIX}/jail.sh $@
		;;
	testport)
		exec env -i PATH=${PATH} VERSION="${VERSION}" SAVED_TERM=${SAVED_TERM} /bin/sh ${SETX} ${POUDRIEREPREFIX}/testport.sh $@
		;;
	bulk)
		exec env -i PATH=${PATH} VERSION="${VERSION}" /bin/sh ${SETX} ${POUDRIEREPREFIX}/bulk.sh $@
		;;
	distclean)
		exec env -i PATH=${PATH} VERSION="${VERSION}" /bin/sh ${SETX} ${POUDRIEREPREFIX}/distclean.sh $@
		;;
	ports)
		exec env -i PATH=${PATH} VERSION="${VERSION}" /bin/sh ${SETX} ${POUDRIEREPREFIX}/ports.sh $@
		;;
	queue)
		exec env -i PATH=${PATH} VERSION="${VERSION}" /bin/sh ${SETX} ${POUDRIEREPREFIX}/queue.sh $@
		;;
	options)
		exec env -i TERM=${SAVED_TERM} PATH=${PATH} VERSION="${VERSION}" /bin/sh ${SETX} ${POUDRIEREPREFIX}/options.sh $@
		;;
	help)
		usage
		;;
	version)
		echo "${VERSION}"
		;;
	daemon)
		exec env -i PATH=${PATH} VERSION="${VERSION}" /bin/sh ${SETX} ${POUDRIEREPREFIX}/daemon.sh $@
		;;
	*)
		echo "Unknown command ${CMD}"
		usage
		;;
esac
