#! /bin/sh
# $FreeBSD: head/Mk/Scripts/plist_sub_sed_sort.sh 475361 2018-07-26 11:09:46Z mat $
#
# MAINTAINER: portmgr@FreeBSD.org
#
# PLIST_SUB_SED helper to sort by longest value first.

awk '{
	while (match($0, /s![^!]*![^!]*!g;/)) {
		sedp=substr($0, RSTART, RLENGTH)
		$0=substr($0, RSTART+RLENGTH)
		split(sedp, a, "!")
		# Convert \. to . for sorting.
		gsub(/\\./, ".", a[2])
		print length(a[2]), sedp
	}
}' | sort -rn | awk '{$1=""; print $0}' > $1
