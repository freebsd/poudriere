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

if [ -z "${PORTSDIR}" ]; then
       err 1 "No ports directory defined."
fi

# create needed directories
if [ ! -d "$PORTSNAPDIR" ]; then
	mkdir -p $PORTSNAPDIR 
fi
if [ ! -d "$PORTSDIR" ]; then
	mkdir -p $PORTSDIR
fi

# actually install or update the portstree
if [ ! -f $PORTSNAPDIR/INDEX ]; then
	msg "Extracting portstree"
	/usr/sbin/portsnap -d $PORTSNAPDIR -p $PORTSDIR fetch extract > /dev/null
else
	msg "Updating portstree"
	/usr/sbin/portsnap -d $PORTSNAPDIR -p $PORTSDIR fetch update > /dev/null
fi
