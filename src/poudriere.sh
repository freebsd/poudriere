#!/bin/sh

usage() {
	echo "pourdriere cmd [options]"
	echo 
	echo "cmd can be:"
	echo "- createjail: create a new jail to test ports"
	echo "- removejail: remove the jail whose name is given to the -n option"
	echo "- startjail: start the jail whose name is given to the -n option"
	echo "- stopjail: stop the jail whose name is given to the -n option"
	echo "- testport: launch a test on a given port"
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
	*)
	echo "unknown command $1"
	usage
	;;
esac
