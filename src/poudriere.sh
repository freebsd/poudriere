#!/bin/sh

usage() {
	echo "poudriere cmd [options]"
	echo 
	echo "cmd can be:"
	echo "- createjail: create a new jail to test ports"
	echo "- removejail: remove the jail whose name is given to the -j option"
	echo "- startjail: start the jail whose name is given to the -j option"
	echo "- stopjail: stop the jail whose name is given to the -j option"
	echo "- testport: launch a test on a given port"
	echo "- genpkg: generate package for a given port"
	echo "- bulk: generate packages for given ports"
	echo "- lsjail: list jails created and used by poudriere"
	echo "- ports: create or update the portstree used by poudriere"
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
