#!/bin/sh
set -e

usage() {
	echo "poudriere bulk [options] [-f file|cat/port ...]

Parameters:
    -f file     -- Get the list of ports to build from a file
    [ports...]  -- List of ports to build on the command line

Options:
    -c          -- Clean all the previously built binary packages
    -C          -- Clean previously built packages from the given list to build
    -R          -- Clean RESTRICTED packages after building
    -t          -- Add some tests to the package build
    -s          -- Skip sanity checks
    -J n        -- Run n jobs in parallel (Default: to 8)
    -j name     -- Run only on the given jail
    -p tree     -- Specify on which ports tree the bulk build will be done
    -v          -- Be verbose; show more information. Use twice to enable debug output
    -w          -- Save WRKDIR on failed builds
    -z set      -- Specify which SET to use
    -a          -- Build the whole ports tree"

	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
PTNAME="default"
SKIPSANITY=0
SETNAME=""
CLEAN=0
CLEAN_LISTED=0
ALL=0
. ${SCRIPTPREFIX}/common.sh

[ $# -eq 0 ] && usage

while getopts "f:j:J:Ccn:p:Rtsvwz:a" FLAG; do
	case "${FLAG}" in
		t)
			export PORTTESTING=1
			export DEVELOPER_MODE=yes
			;;
		c)
			CLEAN=1
			;;
		C)
			CLEAN_LISTED=1
			;;
		f)
			LISTPKGS=${OPTARG}
			;;
		j)
			jail_exists ${OPTARG} || err 1 "No such jail: ${OPTARG}"
			JAILNAME=${OPTARG}
			;;
		J)
			PARALLEL_JOBS=${OPTARG}
			;;
		p)
			PTNAME=${OPTARG}
			;;
		R)
			NO_RESTRICTED=1
			;;
		s)
			SKIPSANITY=1
			;;
		w)
			SAVE_WRKDIR=1
			;;
		z)
			[ -n "${OPTARG}" ] || err 1 "Empty set name"
			SETNAME="${OPTARG}"
			;;
		a)
			ALL=1
			;;
		v)
			VERBOSE=$((${VERBOSE:-0} + 1))
			;;
		*)
			usage
			;;
	esac
done

shift $((OPTIND-1))

if [ $# -eq 0 ]; then
	[ -n "${LISTPKGS}" -o ${ALL} -eq 1 ] || err 1 "No packages specified"
	[ ${ALL} -eq 1 -o -f "${LISTPKGS}" ] || err 1 "No such list of packages: ${LISTPKGS}"
else
	[ ${ALL} -eq 0 ] || err 1 "command line arguments and -a cannot be used at the same time"
	[ -z "${LISTPKGS}" ] || err 1 "command line arguments and list of ports cannot be used at the same time"
	LISTPORTS="$@"
fi

export SKIPSANITY

STATUS=0 # out of jail #

test -z "${JAILNAME}" && err 1 "Don't know on which jail to run please specify -j"

MASTERMNT=$(jget ${JAILNAME} mnt)
MASTERNAME=${JAILNAME}-${PTNAME}
[ -n "${SETNAME}" ] && MASTERNAME="${MASTERNAME}-${SETNAME}"

export MASTERNAME
export MASTERMNT
if [ ${CLEAN} -eq 1 ]; then
	msg_n "Cleaning previous bulks if any..."
	rm -rf ${POUDRIERE_DATA}/packages/${MASTERNAME}/*
	rm -rf ${POUDRIERE_DATA}/cache/${JAILNAME}
	echo " done"
fi

export POUDRIERE_BUILD_TYPE=bulk

jail_start ${JAILNAME} ${PTNAME} ${SETNAME}

LOGD=`log_path`
if [ -d ${LOGD} -a ${CLEAN} -eq 1 ]; then
	msg "Cleaning up old logs"
	rm -f ${LOGD}/*.log 2>/dev/null
fi

prepare_ports

bset ${MASTERNAME} status "building:"

mnt=$(my_path)
if [ -z "${PORTTESTING}" -a -z "${ALLOW_MAKE_JOBS}" ]; then
	echo "DISABLE_MAKE_JOBS=yes" >> ${mnt}/etc/make.conf
fi

markfs prepkg ${mnt}

parallel_build ${JAILNAME} ${PTNAME} ${SETNAME} || : # Ignore errors as they are handled below

bset ${MASTERNAME} status "done:"

build_stats 0

failed=$(bget ${MASTERNAME} ports.failed | awk '{print $1 ":" $2 }' | xargs echo)
built=$(bget ${MASTERNAME} ports.built | xargs echo)
ignored=$(bget ${MASTERNAME} ports.ignored | awk '{print $1}' | xargs echo)
skipped=$(bget ${MASTERNAME} ports.skipped | awk '{print $1}' | sort -u | xargs echo)
nbfailed=$(bget ${MASTERNAME} stats_failed)
nbignored=$(bget ${MASTERNAME} stats_ignored)
nbskipped=$(bget ${MASTERNAME} stats_skipped)
nbbuilt=$(bget ${MASTERNAME} stats_built)
[ "$nbfailed" = "-" ] && nbfailed=0
[ "$nbignored" = "-" ] && nbignored=0
[ "$nbskipped" = "-" ] && nbskipped=0
[ "$nbbuilt" = "-" ] && nbbuilt=0
# Package all newly build ports
if [ $nbbuilt -eq 0 ]; then
	if [ $PKGNG -eq 1 ]; then
		msg "No package built, no need to update the repository"
	else
		msg "No package built, no need to update INDEX"
	fi
elif [ $PKGNG -eq 1 ]; then
	if [ -n "${NO_RESTRICTED}" ]; then
		msg "Cleaning restricted packages"
		injail ${MASTERNAME} make -C /usr/ports -j ${PARALLEL_JOBS} clean-restricted
	fi
	msg "Creating pkgng repository"
	bset ${MASTERNAME} status "pkgrepo:"
	injail ${MASTERNAME} tar xf /packages/Latest/pkg.txz -C /
	injail ${MASTERNAME} rm -f /packages/repo.txz /packages/repo.sqlite
	if [ -n "${PKG_REPO_SIGNING_KEY}" -a -f "${PKG_REPO_SIGNING_KEY}" ]; then
		install -m 0400 ${PKG_REPO_SIGNING_KEY} ${mnt}/tmp/repo.key
		injail ${MASTERNAME} pkg-static repo /packages/ /tmp/repo.key
		rm -f ${mnt}/tmp/repo.key
	else
		injail ${MASTERNAME} pkg-static repo /packages/
	fi
else
	if [ -n "${NO_RESTRICTED}" ]; then
		msg "Cleaning restricted packages"
		injail ${MASTERNAME} make -C /usr/ports -j ${PARALLEL_JOBS} clean-restricted
	fi
	msg "Preparing INDEX"
	bset ${MASTERNAME} status "index:"
	OSMAJ=`injail ${MASTERNAME} uname -r | awk -F. '{ print $1 }'`
	INDEXF=${POUDRIERE_DATA}/packages/${MASTERNAME}/INDEX-${OSMAJ}
	rm -f ${INDEXF}.1 2>/dev/null || :
	for pkg_file in ${POUDRIERE_DATA}/packages/${MASTERNAME}/All/*.tbz; do
		# Check for non-empty directory with no packages in it
		[ "${pkg}" = "${POUDRIERE_DATA}/packages/${MASTERNAME}/All/*.tbz" ] && break
		msg_verbose "Extracting description for ${ORIGIN} ..."
		ORIGIN=$(pkg_get_origin ${pkg_file})
		[ -d ${PORTSDIR}/${ORIGIN} ] &&	parallel_run "injail ${MASTERNAME} make -C /usr/ports/${ORIGIN} describe >> ${INDEXF}.1"
	done
	parallel_stop

	msg_n "Generating INDEX..."
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
	echo " done"

	rm ${INDEXF}.1
	[ -f ${INDEXF}.bz2 ] && rm ${INDEXF}.bz2
	msg_n "Compressing INDEX-${OSMAJ}..."
	bzip2 -9 ${INDEXF}
	echo " done"
fi

cleanup
if [ $nbbuilt -gt 0 ]; then
	msg_n "Built ports: "
	echo ${built}
	echo ""
fi
if [ $nbfailed -gt 0 ]; then
	msg_n "Failed ports: "
	echo ${failed}
	echo ""
fi
if [ $nbignored -gt 0 ]; then
	msg_n "Ignored ports: "
	echo ${ignored}
	echo ""
fi
if [ $nbskipped -gt 0 ]; then
	msg_n "Skipped ports: "
	echo ${skipped}
	echo ""
fi
msg "[${MASTERNAME}] $nbbuilt packages built, $nbfailed failures, $nbignored ignored, $nbskipped skipped"

set +e

exit $((nbfailed + nbskipped))
