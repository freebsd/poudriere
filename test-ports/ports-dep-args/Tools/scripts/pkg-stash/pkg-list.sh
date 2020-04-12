#!/bin/sh
# $FreeBSD: head/Tools/scripts/pkg-stash/pkg-list.sh 340719 2014-01-22 15:52:06Z mat $

for i in . `make all-depends-list`; do
	cd $i && [ -f "`make -V PKGFILE`" ] && make -V PKGFILE
done
