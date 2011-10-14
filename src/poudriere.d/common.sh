#!/bin/sh

err() {
	if [ $# -ne 2 ]; then
		err 1 "err expects 2 arguments: exit_number \"message\"" >&2
	fi
	[ ${STATUS} -eq 1 ] && cleanup
	echo "$2" >&2
	exit $1
}

msg_n() {
	echo -n "====>> $1"
}

msg() {
	echo "====>> $1"
}

sig_handler() {
	if [ ${STATUS} -eq 1 ]; then
		msg "Signal caught, cleaning up and exiting"
		cleanup
	fi
	return ${STATUS}
}

jail_exists() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	zfs list -rH -o poudriere:type,poudriere:name | \
		egrep -q "^rootfs[[:space:]]$1$" && return 0
	return 1
}

jail_runs() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	jls -qj ${1} name > /dev/null 2>&1 && return 0
	return 1
}

jail_get_ip() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	jls -qj ${1} ip4.addr
}

jail_get_base() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	zfs list -rH -o poudriere:type,poudriere:name,mountpoint | \
		awk '/^rootfs[[:space:]]'$1'[[:space:]]/ { print $3 }'
}

jail_get_fs() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	zfs list -rH -o poudriere:type,poudriere:name,name | \
		awk '/^rootfs[[:space:]]'$1'[[:space:]]/ { print $3 }'
}

jail_get_zpool_version() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	FS=`jail_get_fs $1`
	ZVERSION=$(zpool get version ${FS%%/*} | awk '/^'${FS%%/*}'/ { print $3 }')
	echo $ZVERSION
}

jail_ls() {
	zfs list -rH -o poudriere:type,poudriere:name | \
		awk '/^rootfs/ { print $2 }'
}

port_exists() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	zfs list -rH -o poudriere:type,poudriere:name,name | \
		egrep -q "^ports[[:space:]]$1" && return 0
	return 1
}

port_get_base() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	zfs list -rH -o poudriere:type,poudriere:name,mountpoint | \
		awk '/^ports[[:space:]]'$1'/ { print $3 }'
}

port_get_fs() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	zfs list -rH -o poudriere:type,poudriere:name,name | \
		awk '/^ports[[:space:]]'$1'/ { print $3 }'
}

fetch_file() {
	fetch -o $1 $2 || fetch -o $1 $2
}

jail_create_zfs() {
	[ $# -ne 5 ] && err 1 "Fail: wrong number of arguments"
	NAME=$1
	VERSION=$2
	ARCH=$3
	JAILBASE=$( echo $4 | sed -e "s,//,/,g")
	FS=$5
	msg_n "Creating ${NAME} fs..."
	zfs create -p \
		-o poudriere:type=rootfs \
		-o poudriere:name=${NAME} \
		-o poudriere:version=${VERSION} \
		-o poudriere:arch=${ARCH} \
		-o mountpoint=${JAILBASE} ${FS} || err 1 " Fail" && echo " done"
}

add_ips_range () {
	while [ $max1 -ne $min1 ] || [ $max2 -ne $min2 ] ||
		[ $max3 -ne $min3 ] || [ $max4 -ne $min4 ]; do
	if [ $min4 -eq 255 ]; then
		if [ $min3 -eq 255 ]; then
			if [ $min2 -eq 255 ]; then
				min1=$(( min1 + 1))
				min2=0
			else
				min2=$(( min2 + 1))
			fi
			min3=0
		else
			min3=$((min3 + 1))
		fi
		min4=0
	else
		min4=$((min4 + 1))
	fi
	LISTIPS="${LISTIPS} $min1.$min2.$min3.$min4"
	done
}

LISTIPS=""
netmask_to_ips_range() {
			read ip1 ip2 ip3 ip4 <<EOF
			$(IFS=.; echo ${1})
EOF
			read mask1 mask2 mask3 mask4 <<EOF
			$(IFS=.; echo ${2})
EOF

			min1=$((ip1 & mask1))
			min2=$((ip2 & mask2))
			min3=$((ip3 & mask3))
			min4=$((ip4 & mask4))
			min4=$((min4 + 1))

			max1=$((ip1 | (255 ^ mask1)))
			max2=$((ip2 | (255 ^ mask2)))
			max3=$((ip3 | (255 ^ mask3)))
			max4=$((ip4 | (255 ^ mask4)))
			max4=$((max4 - 1))
}

get_ip() {
	test -z ${IPS} && err 1 "No IP pool defined"

	for ip in ${IPS}; do
		IP=`awk -v testip=${ip} '
		BEGIN {
			ip = "([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])"
			ipcidr = "^" ip "\\." ip "\\." ip "\\." ip "\\/[0-9][0-9]$"
			ipmask =  "^" ip "\\." ip "\\." ip "\\." ip "\\/" ip "\\." ip "\\." ip "\\." ip "$"
			iprange = "^" ip "\\." ip "\\." ip "\\." ip "-" ip "\\." ip "\\." ip "\\." ip "$"
			ip = "^" ip "\\." ip "\\." ip "\\." ip "$"
			if (testip ~ ip || testip ~ ipcidr || testip ~ ipmask || testip ~ iprange) {
				print testip
			} else {
				print "bad"
			}
		}'`
		[ ${IP} = "bad" ] && continue
		case ${IP} in
			*/*)
				full=$((${IP#*/} / 8))
				modulo=$((${IP#*/} % 8))
				i=0
				while [ $i -lt 4 ]; do
					if [ $i -lt $full ]; then
						mask="${mask}255"
					elif [ $i -eq $full ]; then
						mask="${mask}$((256 - 32*(8-$modulo)))"
					else
						mask="${mask}0"
					fi
					test $i -lt 3 && mask="${mask}."
					i=$(( i + 1))
				done
				netmask_to_ips_range ${IPS%%/*} ${mask}
				add_ips_range
				;;
			*/*.*)
				netmask_to_ips_range ${IPS%%/*} ${IP#*/}
				add_ips_range
				;;
			*-*)
				read min1 min2 min3 min4 <<EOF
				$(IFS=.; echo ${IP%%-*})
EOF
				read max1 max2 max3 max4 <<EOF
				$(IFS=.; echo ${IP#*-})
EOF
				add_ips_range
				;;
			*)
				LISTIPS="${LISTIPS} ${IP}"
				;;
		esac
	done
	for IP in ${LISTIPS}; do
		if jls ip4.addr | egrep -q "^${IP}$"; then
			continue
		else
			echo ${IP}
			return 0
		fi
	done
}

jail_start() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	NAME=$1
	jail_exists ${NAME} || err 1 "No such jail: ${NAME}"
	IP=`get_ip`
	test -z ${IP} && err 1 "Fail: no IP left"

	if [ "${USE_LOOPBACK}" = "yes" ]; then
		LOOP=0
		while :; do
			LOOP=$(( LOOP += 1))
			ifconfig lo${LOOP} create > /dev/null 2>&1 && break
		done
		msg "Adding loopback lo${LOOP}"
		ifconfig lo${LOOP} inet ${IP} > /dev/null 2>&1
	else
		test -z ${ETH} && err "No ethernet device defined"
	fi
	MNT=`jail_get_base ${NAME}`

	. /etc/rc.subr
	. /etc/defaults/rc.conf

	msg "Mounting devfs"
	devfs_mount_jail "${MNT}/dev"
	msg "Mounting /proc"
	[ ! -d ${MNT}/proc ] && mkdir ${MNT}/proc
	mount -t procfs proc ${MNT}/proc
	msg "Mounting linuxfs"
	[ ! -d ${MNT}/compat/linux/proc ] && mkdir -p ${MNT}/compat/linux/proc
	[ ! -d ${MNT}/compat/linux/sys ] && mkdir -p ${MNT}/compat/linux/sys
	mount -t linprocfs linprocfs ${MNT}/compat/linux/proc
	mount -t linsysfs linsysfs ${MNT}/compat/linux/sys
	if [ ! "${USE_LOOPBACK}" = "yes" ]; then
		msg "Adding IP alias"
		ifconfig ${ETH} inet ${IP} alias > /dev/null 2>&1
	fi
	test -n "${RESOLV_CONF}" && cp -v "${RESOLV_CONF}" "${MNT}/etc/"
	msg "Starting jail ${NAME}"
	jail -c persist name=${NAME} path=${MNT} host.hostname=${NAME} \
		ip4.addr=${IP} allow.sysvipc allow.raw_sockets \
		allow.socket_af allow.mount
}

jail_stop() {
	[ $# -ne 1 ] && err 1 "Fail: wrong number of arguments"
	NAME=${1}
	jail_runs ${NAME} || err 1 "No such jail running: ${NAME}"

	JAILBASE=`jail_get_base ${NAME}`
	IP=`jail_get_ip ${NAME}`
	msg "Stopping jail"
	jail -r ${NAME}
	msg "Umounting file systems"
	for MNT in $( mount | awk -v mnt="${JAILBASE}/" 'BEGIN{ gsub(/\//, "\\\/", mnt); } { if ($3 ~ mnt && $1 !~ /\/dev\/md/ ) { print $3 }}' |  sort -r ); do umount -f ${MNT}
	done

	if [ -n "${MFSSIZE}" ]; then
		MDUNIT=$(mount | awk -v mnt="${JAILBASE}/" 'BEGIN{ gsub(/\//, "\\\/", mnt); } { if ($3 ~ mnt && $1 ~ /\/dev\/md/ ) { sub(/\/dev\/md/, "", $1); print $1 }}')
		umount ${JAILBASE}/wrkdirs
		mdconfig -d -u ${MDUNIT}
	fi
	if [ "${USE_LOOPBACK}" = "yes" ]; then
		LOOP=0
		while :; do
			LOOP=$(( LOOP += 1))
			if ifconfig lo${LOOP} | grep ${IP} > /dev/null 2>&1 ; then
				msg "Removing loopback lo${LOOP}"
				ifconfig lo${LOOP} destroy && break
			fi
		done
	else
		msg "Removing IP alias ${NAME}"
		ifconfig ${ETH} inet ${IP} -alias
	fi
	zfs rollback ${ZPOOL}/poudriere/${NAME}@clean
}

port_create_zfs() {
	[ $# -ne 3 ] && err 2 "Fail: wrong number of arguments"
	NAME=$1
	MNT=$( echo $2 | sed -e 's,//,/,g')
	FS=$3
	msg_n "Creating ${NAME} fs..."
	zfs create -p \
		-o mountpoint=${MNT} \
		-o poudriere:type=ports \
		-o poudriere:name=${NAME} \
		${FS} || err 1 " Fail" && echo " done"
		
}

cleanup() {
	[ -e ${PIPE} ] && rm -f ${PIPE}
	FS=`jail_get_fs ${JAILNAME}`
	zfs destroy ${FS}@bulk 2>/dev/null || :
	zfs destroy ${FS}@prepkg 2>/dev/null || :
	zfs destroy ${FS}@prebuild 2>/dev/null || :
	jail_stop ${JAILNAME}
}

injail() {
	jexec -U root ${JAILNAME} $@
}

build_pkg() {
	local port=$1
	local portdir="/usr/ports/${port}"
	test -d ${JAILBASE}/${portdir} || {
		msg "No such port ${port}"
		return 1
	}
	local LATEST_LINK=$(injail make -C ${portdir} -VLATEST_LINK)
	local PKGNAME=$(injail make -C ${portdir} -VPKGNAME)

	# delete older one if any
	if [ -e ${PKGDIR}/Latest/${LATEST_LINK}.${EXT} ]; then
		PKGNAME_PREV=$(realpath ${PKGDIR}/Latest/${LATEST_LINK}.${EXT})
		if [ "${PKGNAME_PREV##*/}" = "${PKGNAME}.${EXT}" ]; then
			msg "$PKGNAME already packaged skipping"
			return 2
		else
			msg "Deleting previous version of ${port}"
			find ${PKGDIR}/ -name ${PKGNAME_PREV##*/} -delete
			find ${PKGDIR}/ -name ${LATEST_LINK}.${EXT} -delete
		fi
	fi

	msg "Cleaning up wrkdir"
	rm -rf ${JAILBASE}/wrkdirs/*

	msg "Building ${port}"
	injail make -C ${portdir} clean package
	if [ $? -eq 0 ]; then
		STATS_BUILT=$(($STATS_BUILT + 1))
		return 0
	else
		STATS_FAILED=$(($STATS_FAILED + 1))
		FAILED_PORTS="$FAILED_PORTS ${PORTDIRECTORY#*/usr/ports/}"
		return 1
	fi
}

process_deps() {
	tmplist=$1
	tmplist2=$2
	tmplist3=$3
	local port=$4
	local PORTDIRECTORY="/usr/ports/${port}"
	grep -q "$port" ${tmplist} && return
	echo $port >> ${tmplist}
	deps=0
	local m
	for m in `injail make -C ${PORTDIRECTORY} missing`; do
		process_deps "${tmplist}" "${tmplist2}" "${tmplist3}" "$m"
		echo $m $port >> ${tmplist2}
		deps=1
	done
	if [ $deps -eq 0 ] ;then
		echo $port >> ${tmplist3}
	fi
}

prepare_ports() {
	tmplist=`mktemp /tmp/orderport.XXXXXX`
	tmplist2=`mktemp /tmp/orderport2.XXXXX`
	tmplist3=`mktemp /tmp/orderport3.XXXXX`
	touch ${tmplist}
	if [ -z "${LISTPORTS}" ]; then
		for port in `grep -v -E '(^[[:space:]]*#|^[[:space:]]*$)' ${LISTPKGS}`; do
			process_deps "${tmplist}" "${tmplist2}" "$tmplist3" "${port}"
		done
	else
		for port in ${LISTPORTS}; do
			process_deps "${tmplist}" "${tmplist2}" "$tmplist3" "${port}"
		done
	fi
	tsort ${tmplist2} | while read port; do
		grep -q ${port} ${tmplist3} || echo $port >> ${tmplist3}
	done
	cat ${tmplist3}
	rm -f ${tmplist} ${tmplist2} ${tmplist3}
}

prepare_jail() {
	POUDRIERE_PORTSDIR=`port_get_base ${PTNAME}`/ports
	[ -z "${JAILBASE}" ] && err 1 "No path of the base of the jail defined"
	[ -z "${POUDRIERE_PORTSDIR}" ] && err 1 "No ports directory defined"
	[ -z "${PKGDIR}" ] && err 1 "No package directory defined"
	[ -n "${MFSSIZE}" -a -n "${USE_TMPFS}" ] && err 1 "You can't use both tmpfs and mdmfs"

	mount -t nullfs ${POUDRIERE_PORTSDIR} ${JAILBASE}/usr/ports || err 1 "Failed to mount the ports directory "

	[ -d ${POUDRIERE_PORTSDIR}/packages ] || mkdir -p ${POUDRIERE_PORTSDIR}/packages
	[ -d ${PKGDIR}/All ] || mkdir -p ${PKGDIR}/All

	mount -t nullfs ${PKGDIR} ${JAILBASE}/usr/ports/packages || err 1 "Failed to mount the packages directory "
	if [ -n "${DISTFILES_CACHE}" -a -d "${DISTFILES_CACHE}" ]; then
		mount -t nullfs ${DISTFILES_CACHE} ${JAILBASE}/usr/ports/distfiles || err 1 "Failed to mount the distfile directory"
	fi

	[ -n "${MFSSIZE}" ] && mdmfs -M -S -o async -s ${MFSSIZE} md ${JAILBASE}/wrkdirs
	[ -n "${USE_TMPFS}" ] && mount -t tmpfs tmpfs ${JAILBASE}/wrkdirs

	if [ -d ${SCRIPTPREFIX}/../../etc/poudriere.d ]; then
		[ -f ${SCRIPTPREFIX}/../../etc/poudriere.d/make.conf ] && cat ${SCRIPTPREFIX}/../../etc/poudriere.d/make.conf >> ${JAILBASE}/etc/make.conf
		[ -f ${SCRIPTPREFIX}/../../etc/poudriere.d/${JAILNAME}-make.conf ] && cat ${SCRIPTPREFIX}/../../etc/poudriere.d/${JAILNAME}-make.conf >> ${JAILBASE}/etc/make.conf
	fi

	if [ -d ${SCRIPTPREFIX}/../../etc/poudriere.d/${JAILNAME}-options ]; then
		mount -t nullfs ${SCRIPTPREFIX}/../../etc/poudriere.d/${JAILNAME}-options ${JAILBASE}/var/db/ports || err 1 "Failed to mount OPTIONS directory"
	elif [ -d ${SCRIPTPREFIX}/../../etc/poudriere.d/options ]; then
		mount -t nullfs ${SCRIPTPREFIX}/../../etc/poudriere.d/options ${JAILBASE}/var/db/ports || err 1 "Failed to mount OPTIONS directory"
	fi

	msg "Populating LOCALBASE"
	injail /usr/sbin/mtree -q -U -f /usr/ports/Templates/BSD.local.dist -d -e -p /usr/local >/dev/null
}

RESOLV_CONF=""

test -f ${SCRIPTPREFIX}/../../etc/poudriere.conf || err 1 "Unable to find ${SCRIPTPREFIX}/../../etc/poudriere.conf"
. ${SCRIPTPREFIX}/../../etc/poudriere.conf

test -z ${ZPOOL} && err 1 "ZPOOL variable is not set"

trap sig_handler SIGINT SIGTERM SIGKILL EXIT

PIPE=/tmp/poudriere$$.pipe
STATUS=0 # out of jail #
LOGS="${POUDRIERE_DATA}/logs"


# Test if spool exists
zpool list ${ZPOOL} >/dev/null 2>&1 || err 1 "No such zpool : ${ZPOOL}"
ZVERSION=$(zpool get version ${ZPOOL} | awk '/^'${ZPOOL}'/ { print $3 }')
