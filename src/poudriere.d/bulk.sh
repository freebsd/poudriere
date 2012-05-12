#!/bin/sh
set -e

usage() {
	echo "poudriere bulk parameters [options]

Parameters:
    -f file     -- Give the list of ports to build

Options:
    -k          -- Keep the previous built binary packages
    -t          -- Add some testings to package building
    -j name     -- Run only on the given jail
    -p tree     -- Specify on which ports tree the bulk will be done"

	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
PTNAME="default"
KEEP=0
. ${SCRIPTPREFIX}/common.sh

while getopts "f:j:kp:t" FLAG; do
	case "${FLAG}" in
		t)
			export PORTTESTING=1
			;;
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

for JAILNAME in ${JAILNAMES}; do
	PKGDIR=${POUDRIERE_DATA}/packages/${JAILNAME}-${PTNAME}
	jail_start ${JAILNAME}

	if [ ${KEEP} -ne 1 ]; then
		msg_n "Cleaning previous bulks if any..."
		rm -rf ${PKGDIR}/*
		echo " done"
	fi

	prepare_jail

	prepare_ports
	zfs snapshot ${JAILFS}@prepkg
	queue=$(status_get poudriere:queue)
	for port in $queue; do
		build_pkg ${port}
		zfs rollback -r ${JAILFS}@prepkg
	done
	zfs destroy -r ${JAILFS}@prepkg

	failed=$(zfs_get poudriere:stats_failed)
	built=$(zfs_get poudriere:stats_built)
	[ "$failed" = "-" ] && failed=0
	[ "$built" = "-" ] && built=0
# Package all newly build ports
	if [ $built -eq 0 ]; then
		if [ $PKGNG -eq 1 ]; then
			msg "No package built, no need to update the repository"
		else
			msg "No package built, no need to update INDEX"
		fi
	elif [ $PKGNG -eq 1 ]; then
		msg "Packaging all installed ports"
		injail tar xf /usr/ports/packages/Latest/pkg.txz -C /
		injail rm -f /usr/ports/packages/repo.txz
		injail pkg-static repo /usr/ports/packages/
	else
		msg "Preparing index"
		OSMAJ=`injail uname -r | awk -F. '{ print $1 }'`
		INDEXF=${PKGDIR}/INDEX-${OSMAJ}
		for pkg_file in `ls ${PKGDIR}/All/*.tbz`; do
			msg_n "extracting description from `basename ${pkg_file}`"
			ORIGIN=`/usr/sbin/pkg_info -qo ${pkg_file}`
			[ -d ${PORTSDIR}/${ORIGIN} ] && injail make -C /usr/ports/${ORIGIN} describe >> ${INDEXF}.1
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

	cleanup
	msg "$built packages built, $failed failures"
	if [ $built -gt 0 ]; then
		msg_n "Built ports: "
		status_get poudriere:built
	fi
	if [ $failed -gt 0 ]; then
		msg_n "Failed ports: "
		status_get poudriere:failed
	fi
done

set +e

exit $failed
