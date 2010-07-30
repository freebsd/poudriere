#!/bin/sh

usage() {
	echo "pourdriere createJail -n name -v version [-a architecture] [-z zfs] -m [FTP|NONE] "
	echo "by default architecture is the same as the host (amd64 can create i386 jails)"
	echo "by default a new zfs filesystem will be created in the dedicated pool"
	echo "by default the FTP method is used but you can add you home made jail with NONE -v and -a will be ignored in that case"
	exit 1
}

err() {
	if [ $# -ne 2 ]; then
		err 1 "err expects 2 arguments: exit_number \"message\""
	fi
	echo "$2"
	exit $1
}

create_base_fs() {
	echo -n "===> Creating basefs:"
	zfs create -o mountpoint=${BASEFS:=/usr/local/poudriere} $ZPOOL/poudriere >/dev/null 2>&1 || err 1 " Fail" && echo " done"
}

ARCH=`uname -m`
METHOD="FTP"

test -f /usr/local/etc/poudriere.conf || err 1 "Unable to find /usr/local/etc/poudriere.conf"

. /usr/local/etc/poudriere.conf

test -z $ZPOOL && err 1 "ZPOOL variable is not set"

# Test if spool exists
zpool list $ZPOOL >/dev/null 2>&1 || err 1 "No such zpool : $ZPOOL"

#Test if the default FS for pourdriere exists if not creates it
zfs list $ZPOOL/poudriere >/dev/null 2>&1 || create_base_fs

while getopts "n:v:a:z:i:m:" FLAG; do
	case "$FLAG" in
		n)
		NAME=$OPTARG
		;;
		v)
		VERSION=$OPTARG
		;;
		a)
		if [ `uname -m` != "amd64" ]; then
			err 1 "Only amd64 host can choose another architecture"
		fi
		ARCH=$OPTARG
		;;
		z)
		FS=$OPTARG
		;;
		m)
		METHOD=$OPTARG
		;;
		*)
			usage
		;;
	esac
done

test -z $NAME && usage

if [ "$METHOD" = "FTP" ]; then
	test -z $VERSION && usage
fi

# Test if a jail with this name already exists
zfs list -r $ZPOOL/poudriere/$NAME >/dev/null 2>&1 && err 2 "The jail $NAME already exists"

JAILBASE=${BASEFS:=/usr/local/poudriere}/jails/$NAME
# Create the jail FS
echo -n "====> Creating $NAME fs:"
zfs create -o mountpoint=${JAILBASE} $ZPOOL/poudriere/$NAME >/dev/null 2>&1 || err 1 " Fail" && echo " done"


#We need to fetch base and src (for drivers)
echo "====> Fetching base sets for FreeBSD $VERSION $ARCH"
PKGS=`echo "ls base*"| ftp -aV ftp://${FTPHOST:=ftp.freebsd.org}/pub/FreeBSD/releases/$ARCH/$VERSION/base/ | awk '{print $NF}'`
mkdir $JAILBASE/fromftp
for pkg in $PKGS; do
# Let's retry at least one time
	fetch -o $JAILBASE/fromftp/$pkg ftp://${FTPHOST}/pub/FreeBSD/releases/$ARCH/$VERSION/base/$pkg || fetch -o $JAILBASE/fromftp/$pkg ftp://${FTPHOST}/pub/FreeBSD/releases/$ARCH/$VERSION/base/$pkg
done
echo -n "====> Extracting base:"
cat $JAILBASE/fromftp/base.* | tar --unlink -xpzf - -C $JAILBASE/ || err 1 " Fail" && echo " done"
echo -n "====> Cleaning Up base sets:"
rm $JAILBASE/fromftp/*
echo " done"

echo "====> Fetching ssys sets"
PKGS=`echo "ls ssys*"| ftp -aV ftp://${FTPHOST:=ftp.freebsd.org}/pub/FreeBSD/releases/$ARCH/$VERSION/src/ | awk '{print $NF}'`
for pkg in $PKGS; do
# Let's retry at least one time
	fetch -o $JAILBASE/fromftp/$pkg ftp://${FTPHOST}/pub/FreeBSD/releases/$ARCH/$VERSION/src/$pkg || fetch -o $JAILBASE/fromftp/$pkg ftp://${FTPHOST}/pub/FreeBSD/releases/$ARCH/$VERSION/src/$pkg
done
echo -n "====> Extracting ssys:"
cat $JAILBASE/fromftp/ssys.* | tar --unlink -xpzf - -C $JAILBASE/ || err 1 " Fail" && echo " done"
echo -n "====> Cleaning Up ssys sets:"
rm $JAILBASE/fromftp/*
echo " done"

rmdir $JAILBASE/fromftp

OSVERSION=`awk '/\#define __FreeBSD_version/ { print $3 }' $JAILBASE/usr/include/sys/param.h`

LOGIN_ENV=",UNAME_r=$VERSION,UNAME_v=FreeBSD $VERSION,OSVERSION=$OSVERSION"

if [ "$ARCH" = "i386" -a `uname -m` = "amd64" ];then
LOGIN_ENV="$LOGIN_ENV,UNAME_p=i386,UNAME_m=i386"
cat >  $JAILBASE/etc/make.conf << EOF
MACHINE=i386
MACHINE_ARCH=i386
EOF

fi

sed -i .back -e "s/:\(setenv.*\):/:\1$LOGIN_ENV:/" $JAILBASE/etc/login.conf
cap_mkdb $JAILBASE/etc/login.conf
pwd_mkdb -d $JAILBASE/etc/ -p $JAILBASE/etc/master.passwd

cp /etc/resolv.conf $JAILBASE/etc

cat > $JAILBASE/poudriere-jail.conf << EOF
Version: $VERSION
Arch: $ARCH
EOF

cat > $JAILBASE/etc/rc.conf << EOF
sendmail_submit_enable="NO"
sendmail_outbound_enable="NO"
sendmail_msp_queue_enable="NO"
sendmail_enable="NO"
cron_enable="NO"
EOF

zfs snapshot $ZPOOL/poudriere/$NAME@clean
echo "====> Jail $NAME $VERSION $ARCH is ready to be used"
