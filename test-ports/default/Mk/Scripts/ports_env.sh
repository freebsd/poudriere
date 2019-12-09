#! /bin/sh

# MAINTAINER: portmgr@FreeBSD.org
# $FreeBSD: head/Mk/Scripts/ports_env.sh 399171 2015-10-13 00:03:10Z bdrewery $

if [ -z "${SCRIPTSDIR}" ]; then
	echo "Must set SCRIPTSDIR" >&2
	exit 1
fi

. ${SCRIPTSDIR}/functions.sh

export_ports_env
