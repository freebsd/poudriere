#!/bin/sh
set -e

usage() {
	echo "poudriere bulk parameters [options]"
cat <<EOF

Parameters:
    -f file     -- Give the list of ports to build

Options:
    -k          -- Keep the previous built binary packages
    -j name     -- Run only on the given jail
    -p tree     -- Specify on which ports tree the bulk will be done
EOF
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
PTNAME="default"
KEEP=0
. ${SCRIPTPREFIX}/common.sh

LOGS="${POUDRIERE_DATA}/logs"

while getopts "f:j:kp:" FLAG; do
	case "${FLAG}" in
		k)
			KEEP=1
			;;
		f)
			LISTPKGS=${OPTARG}
			;;
		j)
			jail_exists ${OPTARG} || err 1 "No such jail: ${OPTARG}"
			JAILNAMES="${JAILNAMES} ${OPTARG}"
			;;
		p)
			PTNAME=${OPTARG}
			;;
		*)
			usage
			;;
	esac
done

test -z ${LISTPKGS} && usage
test -f ${LISTPKGS} || err 1 "No such list of packages: ${LISTPKGS}"

STATUS=0 # out of jail #

test -z "${JAILNAMES}" && JAILNAMES=`jail_ls`

STATS_BUILT=0
STATS_FAILED=0
FAILED_PORTS=""

for JAILNAME in ${JAILNAMES}; do
	PKGNG=0
	EXT=tbz
	JAILBASE=`jail_get_base ${JAILNAME}`
	JAILFS=`jail_get_fs ${JAILNAME}`
	[ -x ${JAILBASE}/usr/sbin/pkg ] && PKGNG=1
	PKGDIR=${POUDRIERE_DATA}/packages/bulk-${JAILNAME}
	jail_start ${JAILNAME}

	STATUS=1 #injail

	if [ ${KEEP} -ne 1 ]; then
		msg_n "Cleaning previous bulks if any..."
		rm -rf ${POUDRIERE_DATA}/packages/bulk-${JAILNAME}/*
		echo " done"
	fi

	prepare_jail

	[ $PKGNG -eq 1 ] && EXT=txz

	exec 3>&1 4>&2
	[ ! -e ${PIPE} ] && mkfifo ${PIPE}
	tee ${LOGS}/bulk-${JAILNAME}.log < ${PIPE} >&3 &
	tpid=$!
	exec > ${PIPE} 2>&1

	zfs snapshot ${JAILFS}@bulk
	for port in `grep -v -E '(^[[:space:]]*#|^[[:space:]]*$)' ${LISTPKGS}`; do
		PORTDIRECTORY="/usr/ports/${port}"

		test -d ${JAILBASE}/${PORTDIRECTORY} || {
			msg "No such port ${port}"
			continue
		}

		PKGNAME=$(jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} -VPKGNAME)
		if [ -f ${POUDRIERE_DATA}/packages/bulk-${JAILNAME}/All/${PKGNAME}.${EXT} ]; then
			msg "$PKGNAME already packaged skipping"
			continue
		fi
		zfs rollback ${JAILFS}@bulk
		rm -rf ${JAILBASE}/wrkdirs/*
		msg "building ${port}"
		jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} clean install
		if [ $? ]; then
			STATS_BUILT=$((STATS_BUILT+1))
		else
			STATS_FAILED=$((STATS_FAILED+1))
			FAILED_PORTS="$FAILED_PORTS ${PORTDIRECTORY#*/usr/ports/}"
		fi
		msg "packaging"
		if [ $PKGNG -eq 1 ]; then
			for pkg in `jexec -U root ${JAILNAME} /usr/sbin/pkg info -qa`; do
				[ -f ${POUDRIERE_DATA}/packages/bulk-${JAILNAME}/All/${pkg}.${EXT} ] && continue
				msg "packaging ${pkg}"
				pkgorig=`jexec -U root ${JAILNAME} /usr/sbin/pkg info -q -o ${pkg}`
				jexec -U root ${JAILNAME} make -C /usr/ports/${pkgorig} package || continue
			done
		else
			for pkg in `jexec -U root ${JAILNAME} /usr/sbin/pkg_info | awk '{ print $1 }'`; do
				[ -f ${POUDRIERE_DATA}/packages/bulk-${JAILNAME}/All/${pkg}.${EXT} ] && continue
				msg "packaging ${pkg}"
				pkgorig=`jexec -U root ${JAILNAME} /usr/sbin/pkg_info -qo ${pkg}`
				jexec -U root ${JAILNAME} make -C /usr/ports/${pkgorig} package
			done
		fi
	done
	zfs destroy ${JAILFS}@bulk 2>/dev/null || :

# Package all newly build ports
	if [ $STATS_BUILT -eq 0 ]; then
		msg "No package built, no need to update INDEX"
	elif [ $PKGNG -eq 1 ]; then
		msg "Packaging all installed ports"
		jexec -U root ${JAILNAME} /usr/sbin/pkg repo /usr/ports/packages/All/
	else
		msg "Preparing index"
		OSMAJ=`jexec -U root ${JAILNAME} uname -r | awk -F. '{ print $1 }'`
		INDEXF=${POUDRIERE_DATA}/packages/bulk-${JAILNAME}/INDEX-${OSMAJ}
		for pkg_file in `ls ${POUDRIERE_DATA}/packages/bulk-${JAILNAME}/All/*.tbz`; do
			msg_n "extracting description from `basename ${pkg_file}`"
			ORIGIN=`/usr/sbin/pkg_info -qo ${pkg_file}`
			[ -d ${POUDRIERE_PORTSDIR}/${ORIGIN} ] && jexec -U root ${JAILNAME} make -C /usr/ports/${ORIGIN} describe >> ${INDEXF}.1
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


msg "$STATS_BUILT packages built, $STATS_FAILED failures"
if [ ! -z $FAILED_PORTS ]; then
	msg "Failed ports:$FAILED_PORTS"
fi
exit $STATS_FAILED
