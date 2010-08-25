#!/bin/sh

usage() {
	echo "pourdriere cmd [options]"
	echo 
	echo "cmd can be:"
	echo "- createjail: create a new jail to test ports"
	echo "- testport: launch a test on a given ports"
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
	testport)
		shift
		/bin/sh ${POUDRIEREPREFIX}/share/poudriere/test_ports.sh $@
	;;
	*)
	echo "unknown command $1"
	usage
	;;
esac
