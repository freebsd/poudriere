#!/bin/sh
set -e

usage() {
	echo "poudriere bulk -f listpkgs [-c] [-j jailname]"
	echo "-f <listpkgs>: list of packages to build"
	echo "-c run make config for the given port"
	echo "-j <jailname> run only on the given jail"
	echo "-C cleanup the old bulk"
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
CONFIGSTR=0
CLEAN=0
. ${SCRIPTPREFIX}/common.sh

LOGS="${POUDRIERE_DATA}/logs"

while getopts "Cf:cnj:" FLAG; do
	case "${FLAG}" in
		c)
		CONFIGSTR=1
		;;
		C)
		CLEAN=1
		;;
		f)
		LISTPKGS=${OPTARG}
		;;
		j)
		zfs list ${ZPOOL}/poudriere/${OPTARG} >/dev/null 2>&1 || err 1 "No such jail: ${OPTARG}"
		JAILNAMES="${JAILNAMES} ${OPTARG}"
		;;
		*)
		usage
		;;
	esac
done

test -z ${LISTPKGS} && usage
test -f ${LISTPKGS} || err 1 "No such list of packages: ${LISTPKGS}"

STATUS=0 # out of jail #

test -z ${JAILNAMES} && JAILNAMES=`zfs list -rH ${ZPOOL}/poudriere | awk '/^'${ZPOOL}'\/poudriere\// { sub(/^'${ZPOOL}'\/poudriere\//, "", $1); print $1 }'`

for JAILNAME in ${JAILNAMES}; do
	JAILBASE=`zfs list -H -o mountpoint ${ZPOOL}/poudriere/${JAILNAME}`
	PKGDIR=${POUDRIERE_DATA}/packages/bulk-${JAILNAME}
	/bin/sh ${SCRIPTPREFIX}/start_jail.sh -j ${JAILNAME}

	STATUS=1 #injail

	if [ ${CLEAN} -eq 1 ]; then
		msg_n "Cleaning previous bulks if any..."
		rm -rf ${POUDRIERE_DATA}/packages/bulk-${JAILNAME}/*
		echo " done"
	fi

	prepare_jail

	exec 3>&1 4>&2
	[ ! -e ${PIPE} ] && mkfifo ${PIPE}
	tee ${LOGS}/bulk-${JAILNAME}.log < ${PIPE} >&3 &
	tpid=$!
	exec > ${PIPE} 2>&1

	for port in `grep -v -E '(^[[:space:]]*#|^[[:space:]]*$)' ${LISTPKGS}`; do
		PORTDIRECTORY="/usr/ports/${port}"

		test -d ${JAILBASE}/${PORTDIRECTORY} || {
			msg "No such port ${port}"
			continue
		}

		msg "building ${port}"
		jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} install
	done

# Package all newly build ports
	msg "Packaging all installed ports"
	if [ -x ${JAILBASE}/usr/sbin/pkg ]; then
		jexec -U root ${JAILNAME} /usr/sbin/pkg create -a -o /usr/ports/packages/All/
	else
		OSMAJ=`jexec -U root ${JAILNAME} uname -r | awk -F. '{ print $1 }'`
		INDEXF=${POUDRIERE_DATA}/packages/bulk-${JAILNAME}/INDEX-${OSMAJ}
		for pkg in `jexec -U root ${JAILNAME} /usr/sbin/pkg_info | awk '{ print $1 }' `; do
			msg_n "packaging ${pkg}"
			ORIGIN=`jexec -U root ${JAILNAME} /usr/sbin/pkg_info -qo ${pkg}`
			jexec -U root ${JAILNAME} make -C /usr/ports/${ORIGIN} package > /dev/null
			echo " done"
		done

		for pkg_file in `ls ${POUDRIERE_DATA}/packages/bulk-${JAILNAME}/All/*.tbz`; do
			msg_n "extracting description from `basename ${pkg_file}`"
			ORIGIN=`/usr/sbin/pkg_info -qo ${pkg_file}`
			[ -d /usr/ports/${ORIGIN} ] && jexec -U root ${JAILNAME} make -C /usr/ports/${ORIGIN} describe >> ${INDEXF}.1
			echo " done"
		done

		awk -v indf=${INDEXF}.1 -F\| 'BEGIN {
		nblines=0
		while ((getline < indf) > 0) {
		sub(/\//, "\/", $2);
		patterns[nblines] = "^"$2"$";
		subst[nblines] = $1;
		a_edep[nblines] = $8;
		a_pdep[nblines] = $9;
		a_fdep[nblines] = $10;
		a_bdep[nblines] = $11;
		a_rdep[nblines] = $12;
		nblines++;
		}
		OFS="|"}
		{

		edep = $8;
		pdep = $9;
		fdep = $10;
		bdep = $11;
		rdep = $12;

		split($8, sedep, " ") ;
		split($9, sfdep, " ") ;
		split($10, spdep, " ") ;
		split($11, sbdep, " ") ;
		split($12, srdep, " ") ;

		for (i = 0; i < nblines; i++) {
			for (s in sedep)
				if ( sedep[s] ~ patterns[i] )
					edep = edep" "a_rdep[i];

			for (s in sfdep)
				if ( sfdep[s] ~ patterns[i] )
					fdep = fdep" "a_rdep[i];

			for (s in spdep)
				if ( spdep[s] ~ patterns[i] )
					pdep = pdep" "a_rdep[i];

			for (s in sbdep)
				if ( sbdep[s] ~ patterns[i] )
					bdep = bdep" "a_rdep[i];

			for (s in srdep)
				if ( srdep[s] ~ patterns[i] )
					rdep = rdep" "a_rdep[i];
		}

		edep = uniq(edep, patterns, subst);
		fdep = uniq(fdep, patterns, subst);
		pdep = uniq(pdep, patterns, subst);
		bdep = uniq(bdep, patterns, subst);
		rdep = uniq(rdep, patterns, subst);

		sub(/^ /, "", edep);
		sub(/^ /, "", fdep);
		sub(/^ /, "", pdep);
		sub(/^ /, "", bdep);
		sub(/^ /, "", rdep);
		print $1"|"$2"|"$3"|"$4"|"$5"|"$6"|"$7"|"bdep"|"rdep"|"$13"|"edep"|"pdep"|"fdep
		}

		function array_s(array, str, i) {
			for (i in array)
				if (array[i] == str)
					return 0;

			return -1;
		}

		function uniq(as, pat, subst, B) {
			split(as, A, " ");
			as = "";

			for (a in A) {
				if (array_s(B, A[a]) != 0) {
					str = A[a];
					for (j in subst)
						sub(pat[j], subst[j], str);
						
					as = as" "str
					B[i] = A[a];
					i++;
				}
			}

			return as;
		}
		' ${INDEXF}.1 > ${INDEXF}

		rm ${INDEXF}.1
		[ -f ${INDEXF}.bz2 ] && rm ${INDEXF}.bz2
		msg_n "compressing INDEX-${OSMAJ} ..."
		bzip2 -9 ${INDEXF}
		echo " done"
	fi

	exec 1>&3 3>&- 2>&4 4>&-
	wait $tpid

	cleanup
	STATUS=0 #injail
done

