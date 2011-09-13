#!/bin/sh

usage() {
	echo "poudriere removejail parameters [options]"
cat <<EOF

Parameters:
    -j name     -- Specify which jail we remove

Options:
    -l          -- Clean logs
    -p          -- Clean packages
    -a          -- Clean all
EOF

	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

CLEANLOGS=0
CLEANPKGS=0

while getopts "j:clp" FLAG; do
	case "${FLAG}" in 
		j)
		NAME=${OPTARG}
		;;
		p)
		CLEANPKGS=1
		;;
		l)
		CLEANLOGS=1
		;;
		c)
		CLEANLOGS=1
		CLEANPKGS=1
		;;
		*)
		usage
		;;
	esac
done

test -z ${NAME} && usage

jail_exists ${NAME} || err 1 "No such jail: ${NAME}"
JAILBASE=`jail_get_base ${NAME}`
FS=`jail_get_fs ${NAME}`

if /usr/sbin/jls host.hostname | egrep "^${NAME}$" > /dev/null;then
	msg "Found jail in running state. Stoping it."
	/usr/local/bin/poudriere stopjail -n ${NAME}
fi

msg_n "Removing ${NAME} jail..."
zfs destroy -r ${FS}
rmdir ${JAILBASE}

[ ${CLEANPKGS} -eq 1 ] && rm -rf ${POUDRIERE_DATA}/packages/${NAME}
[ ${CLEANLOGS} -eq 1 ] && rm -f ${POUDRIERE_DATA}/logs/*-${NAME}*.log

echo " done"
