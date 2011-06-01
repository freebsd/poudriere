#!/bin/sh

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

PORTSNAPDIR=/usr/local/poudriere/portsnap

# test if there is any args
if [ $# -gt 0 ]; then
	echo "poudriere portsnap"
	echo "    This command does not take any arguments."
	exit 1
fi

# create needed directories
if [ ! -d $PORTSNAPDIR ]; then
	mkdir -p $PORTSNAPDIR 
fi
if [ ! -d $PORTSDIR ]; then
	mkdir -p $PORTSDIR
fi

# actually install or update the portstree
if [ ! -f $PORTSNAPDIR/INDEX ]; then
	/usr/sbin/portsnap -d $PORTSNAPDIR -p $PORTSDIR fetch extract
else
	/usr/sbin/portsnap -d $PORTSNAPDIR -p $PORTSDIR fetch update
fi
