#!/bin/sh

test -f /usr/local/etc/tinder.conf || ( echo "No configuration file found"; exit 1 )

. /usr/local/etc/tinder.conf

test -n "$tinderboxes" || (echo "No tinderboxes configured"; exit 1)

for tinderbox in $tinderboxes; do
	jailname=`awk -F= '/'jail_${tinderbox}_hostname'/ { sub(/"/,"",$2); sub(/"/,"",$2); print $2 }' /etc/rc.conf`
	echo $jailname
	jailpath=`awk -F= '/'jail_${tinderbox}_rootdir'/ { sub(/"/,"",$2); sub(/"/,"",$2); print $2 }' /etc/rc.conf`
	jls -j $jailname && ( echo "Jail $jailname is already running please cleanup"; exit 1)
	mountpoint=`df $jailpath | tail -1  | awk '{ print $1 }'`
	echo "rollback $mountpoint"
	zfs rollback $mountpoint@propre
	/etc/rc.d/jail start $tinderbox
	test -d "${tinderbox_pkgs_path}/${jailname}" || mkdir -p ${tinderbox_pkgs_path}/${jailname}
	mkdir $jailpath/scripts
	mkdir -p $jailpath/usr/ports/packages
	mount -t nullfs /usr/ports $jailpath/usr/ports
	mount -t nullfs ${tinderbox_pkgs_path}/${jailname} $jailpath/usr/ports/packages
	mount -t nullfs ${tinderbox_scripts_dir} $jailpath/scripts
	grep -q BATCH $jailpath/etc/make.conf || echo "BATCH=yes" >> $jailpath/etc/make.conf
	jexec -U root $jailname make -C /usr/ports/ports-mgmt/portmaster install clean
	cp /usr/local/etc/tinderportmaster.rc $jailpath/usr/local/etc/portmaster.rc
	PKGS=""
	jexec -U root $jailname make -C /usr/ports/$1 clean
	for pkg in `jexec -U root $jailname make -C /usr/ports/$1 missing`; do
		PKGS="$PKGS $pkg"
	done
	jexec -U root $jailname env PAGER=true portmaster -G $PKGS
	jexec -U root $jailname  env PAGER=true portmaster -G ports-mgmt/porttools
	jexec -U root $jailname /scripts/test.sh $1 2>&1 1> /home/jails/tinderboxes/logs/$jailname.log
	umount $jailpath/usr/ports/packages
	umount $jailpath/usr/ports
	umount $jailpath/scripts
	/etc/rc.d/jail stop $tinderbox
	mountpoint=`df $jailpath | tail -1  | awk '{ print $1 }'`
	zfs rollback $mountpoint@propre
done
