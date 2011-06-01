#!/bin/sh

usage() {
	echo "poudriere createjail -j jailname -v version [-a architecture] [-z zfs] -m [FTP|NONE] -s"
	echo "by default architecture is the same as the host (amd64 can create i386 jails)"
	echo "by default a new zfs filesystem will be created in the dedicated pool"
	echo "by default the FTP method is used but you can add your home made jail with NONE -v and -a will be ignored in that case"
	echo "-s: install the whole sources some ports my need it (only kernel sources are installed by default)"
	exit 1
}


ARCH=`uname -m`
METHOD="FTP"

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

create_base_fs() {
	msg_n "Creating basefs:"
	zfs create -o mountpoint=${BASEFS:=/usr/local/poudriere} ${ZPOOL}/poudriere >/dev/null 2>&1 || err 1 " Fail" && echo " done"
}

#Test if the default FS for poudriere exists if not creates it
zfs list ${ZPOOL}/poudriere >/dev/null 2>&1 || create_base_fs

SRCS="ssys*"
SRCSNAME="ssys"

while getopts "j:v:a:z:m:s" FLAG; do
	case "${FLAG}" in
		j)
		NAME=${OPTARG}
		;;
		v)
		VERSION=${OPTARG}
		;;
		a)
		if [ `uname -m` != "amd64" ]; then
			err 1 "Only amd64 host can choose another architecture"
		fi
		ARCH=${OPTARG}
		;;
		z)
		FS=${OPTARG}
		;;
		m)
		METHOD=${OPTARG}
		;;
		s)
		SRCS="s*"
		SRCSNAME="sources"
		;;
		*)
			usage
		;;
	esac
done

test -z ${NAME} && usage

if [ "${METHOD}" = "FTP" ]; then
	test -z ${VERSION} && usage
fi

# Test if a jail with this name already exists
zfs list -r ${ZPOOL}/poudriere/${NAME} >/dev/null 2>&1 && err 2 "The jail ${NAME} already exists"

JAILBASE=${BASEFS:=/usr/local/poudriere}/jails/${NAME}
# Create the jail FS
msg_n "Creating ${NAME} fs..."
zfs create -o mountpoint=${JAILBASE} ${ZPOOL}/poudriere/${NAME} >/dev/null 2>&1 || err 1 " Fail" && echo " done"


#We need to fetch base and src (for drivers)
msg_n "Fetching base sets for FreeBSD $VERSION $ARCH"
PKGS=`echo "ls base*"| ftp -aV ftp://${FTPHOST:=ftp.freebsd.org}/pub/FreeBSD/releases/${ARCH}/${VERSION}/base/ | awk '/-r.*/ {print $NF}'`
mkdir ${JAILBASE}/fromftp
for pkg in ${PKGS}; do
# Let's retry at least one time
	fetch -o ${JAILBASE}/fromftp/${pkg} ftp://${FTPHOST}/pub/FreeBSD/releases/${ARCH}/${VERSION}/base/${pkg} || fetch -o ${JAILBASE}/fromftp/${pkg} ftp://${FTPHOST}/pub/FreeBSD/releases/${ARCH}/${VERSION}/base/${pkg}
done
msg_n "Extracting base..."
cat ${JAILBASE}/fromftp/base.* | tar --unlink -xpzf - -C ${JAILBASE}/ || err 1 " Fail" && echo " done"
msg_n "Cleaning Up base sets..."
rm ${JAILBASE}/fromftp/*
echo " done"

msg "Fetching ${SRCSNAME} sets..."
PKGS=`echo "ls ${SRCS}"| ftp -aV ftp://${FTPHOST:=ftp.freebsd.org}/pub/FreeBSD/releases/${ARCH}/${VERSION}/src/ | awk '/-r.*/ {print $NF}'`
for pkg in ${PKGS}; do
# Let's retry at least one time
	fetch -o ${JAILBASE}/fromftp/${pkg} ftp://${FTPHOST}/pub/FreeBSD/releases/${ARCH}/${VERSION}/src/${pkg} || fetch -o ${JAILBASE}/fromftp/${pkg} ftp://${FTPHOST}/pub/FreeBSD/releases/${ARCH}/${VERSION}/src/${pkg}
done
msg "Extracting ${SRCSNAME}:"
for SETS in ${JAILBASE}/fromftp/*.aa; do
	SET=`basename $SETS .aa`
	echo -e "\t- $SET...\c"
	cat ${JAILBASE}/fromftp/${SET}.* | tar --unlink -xpzf - -C ${JAILBASE}/usr/src || err 1 " Fail" && echo " done"
done
msg_n "Cleaning Up ${SRCSNAME} sets..."
rm ${JAILBASE}/fromftp/*
echo " done"

rmdir ${JAILBASE}/fromftp

OSVERSION=`awk '/\#define __FreeBSD_version/ { print $3 }' ${JAILBASE}/usr/include/sys/param.h`

LOGIN_ENV=",UNAME_r=${VERSION},UNAME_v=FreeBSD ${VERSION},OSVERSION=${OSVERSION}"

if [ "${ARCH}" = "i386" -a `uname -m` = "amd64" ];then
LOGIN_ENV="${LOGIN_ENV},UNAME_p=i386,UNAME_m=i386"
cat > ${JAILBASE}/etc/make.conf << EOF
MACHINE=i386
MACHINE_ARCH=i386
EOF

fi

sed -i .back -e "s/:\(setenv.*\):/:\1${LOGIN_ENV}:/" ${JAILBASE}/etc/login.conf
cap_mkdb ${JAILBASE}/etc/login.conf
pwd_mkdb -d ${JAILBASE}/etc/ -p ${JAILBASE}/etc/master.passwd

cat >> ${JAILBASE}/etc/make.conf << EOF
USE_PACKAGE_DEPENDS=yes
BATCH=yes
WRKDIRPREFIX=/wrkdirs
EOF

mkdir -p ${JAILBASE}/usr/ports
mkdir -p ${JAILBASE}/wrkdirs
mkdir -p ${POUDRIERE_DATA}/packages/${NAME}/All
mkdir -p ${POUDRIERE_DATA}/logs

jail -U root -c path=${JAILBASE} command=/sbin/ldconfig -m /lib /usr/lib /usr/lib/compat

cp /etc/resolv.conf ${JAILBASE}/etc

zfs snapshot ${ZPOOL}/poudriere/${NAME}@clean
msg "Jail ${NAME} ${VERSION} ${ARCH} is ready to be used"
