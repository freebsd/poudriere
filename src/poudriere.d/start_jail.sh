#!/bin/sh

usage() {
	echo "poudriere startjail parameters"
cat <<EOF

Parameters:
    -j name     -- Start the given jail
EOF
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

. /etc/rc.subr
. /etc/defaults/rc.conf

while getopts "j:" FLAG; do
	case "${FLAG}" in
		j)
		NAME=${OPTARG}
		;;
		*)
		usage
		;;
	esac
done

test -z ${NAME} && usage

zfs list ${ZPOOL}/poudriere/${NAME} >/dev/null 2>&1 || err 1 "No such jail"

test -z ${IPS} && err 1 "No IP pool defined for poudriere"

/usr/sbin/jls name | egrep -q "^${NAME}$" && err 2 "Jail ${NAME} is already in use."

LISTIPS=""
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
		*/*.*)
			netmask_to_ips_range ${IP%%/*} ${IP#*/}
			add_ips_range

			;;
		*/*)
			full=$((${IP#*/} / 8))
			modulo=$((${IP#*/} % 8))
			i=0
			while [ $i -lt 4 ]; do
				if [ $i -lt $full ]; then
					mask="${mask}255"
				elif [ $i -eq $full ]; then
					mask="${mask}$((256 - 2*(8-$modulo)))"
				else
					mask="${mask}0"
				fi  
				test $i -lt 3 && mask="${mask}."
				i=$(( i + 1))
			done
			netmask_to_ips_range ${IP%%/*} ${mask}
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

SETIP=""
for IP in ${LISTIPS}; do
	if /usr/sbin/jls ip4.addr | egrep -q "^${IP}$"; then
		continue
	else
		SETIP=${IP}
		break
	fi
done

[ -z ${SETIP} ] && err 2 "No IP left from the defined pool"

if [ "${USE_LOOPBACK}" = "yes" ]; then
        LOOP=0
        while :; do
		LOOP=$(( LOOP += 1))
		ifconfig lo${LOOP} create > /dev/null 2>&1 && break
        done
	msg "Adding loopback lo${LOOP}"
        ifconfig lo${LOOP} inet ${IP} > /dev/null 2>&1
else
	test -z ${ETH} && err 1 "No ethernet device defined for poudriere"
fi

MNT=`zfs list -H -o mountpoint ${ZPOOL}/poudriere/${NAME}`
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
	ifconfig ${ETH} inet ${SETIP} alias > /dev/null 2>&1
fi
if [ -n "${RESOLV_CONF}" ]; then
        cp -v "${RESOLV_CONF}" "${MNT}/etc/"
fi
msg "Starting jail ${NAME}"
jail -c persist name=${NAME} path=${MNT} host.hostname=${NAME} ip4.addr=${IP} \
allow.sysvipc allow.raw_sockets allow.socket_af allow.mount
