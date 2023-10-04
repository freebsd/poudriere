set -e
# Common setup for bulk test runs
: ${ALL:=0}
# Avoid injail() for port_var_fetch
INJAIL_HOST=1

. common.sh

# Strip away @DEFAULT if it is the default FLAVOR
fix_default_flavor() {
	local _originspec="$1"
	local var_return="$2"
	local _origin _flavor _flavors _default_flavor

	originspec_decode "${_originspec}" _origin _flavor ''
	[ -z "${_flavor}" ] && return 0
	hash_get origin-flavors "${_origin}" _flavors
	_default_flavor="${_flavors%% *}"
	[ "${_flavor}" = "${FLAVOR_DEFAULT}" ] && _flavor="${_default_flavor}"
	if [ "${_flavor}" != "${FLAVOR_ALL}" ]; then
		[ "${_default_flavor}" = "${_flavor}" ] || return 0
	fi
	setvar "${var_return}" "${_origin}"
}

# Cache all pkgnames involved.  Being single-threaded this is trivial.
# Return 0 to skip the port
# Return 1 to not skip the port
cache_pkgnames() {
	local isdep="$1"
	local originspec="$2"
	local origin dep_origin spec_flavor flavors pkgname default_flavor ignore
	local flavor_originspec ret port_flavor other_flavor subpkg
	local LOCALBASE was_listed_with_flavor
	local -; set -f

	# XXX: This avoids some exists() checks of the *host* here. Need to
	# jail this function.
	export LOCALBASE=/nonexistent

	if hash_get originspec-pkgname "${originspec}" pkgname; then
		hash_get originspec-ignore "${originspec}" ignore
		ret=1
		[ -n "${ignore}" ] && ret=0
		return ${ret}
	fi

	originspec_decode "${originspec}" origin spec_flavor subpkg

	if [ "${spec_flavor}" = "${FLAVOR_DEFAULT}" ]; then
		originspec_encode originspec "${origin}" '' "${subpkg}"
	elif [ "${spec_flavor}" = "${FLAVOR_ALL}" ]; then
		originspec_encode originspec "${origin}" '' "${subpkg}"
	fi

	port_var_fetch_originspec "${originspec}" \
	   PKGNAME pkgname \
	   FLAVORS flavors \
	   FLAVOR port_flavor \
	   IGNORE ignore \
	    _PDEPS='${PKG_DEPENDS} ${EXTRACT_DEPENDS} ${PATCH_DEPENDS} ${FETCH_DEPENDS} ${BUILD_DEPENDS} ${LIB_DEPENDS} ${RUN_DEPENDS}' \
	    '${_PDEPS:C,([^:]*):([^:]*):?.*,\2,:C,^${PORTSDIR}/,,:O:u}' \
	    pdeps || exit 99
	if [ -n "${spec_flavor}" ] && ! hash_isset origin-flavors "${origin}"; then
		# Make sure we grab the proper default flavors and sort it
		# appropriately
		local originspec_default pkgname_default flavors_default \
		      flavor_default tmp x

		originspec_encode originspec_default "${origin}" '' "${subpkg}"
		port_var_fetch_originspec "${originspec_default}" \
		   PKGNAME pkgname_default \
		   FLAVORS flavors_default \
		   FLAVOR flavor_default || exit 99
		case "${flavors_default}" in
		${flavor_default}\ *|${flavor_default}) ;;
		*)
			tmp="${flavor_default}"
			for x in ${flavors_default}; do
				case " ${tmp} " in
				*\ ${x}\ *) ;;
				*) tmp="${tmp:+${tmp} }${x}" ;;
				esac
			done
			flavors_default="${tmp}"
			;;
		esac
		hash_set origin-flavors "${origin}" "${flavors_default}"
		flavors="${flavors_default}"
	elif [ -z "${spec_flavor}" ]; then
		hash_set origin-flavors "${origin}" "${flavors}"
	else
		hash_get origin-flavors "${origin}" flavors || flavors=
	fi
	originspec_encode flavor_originspec "${origin}" "${port_flavor}" "${subpkg}"
	fix_default_flavor "${originspec}" originspec
	assert_not '' "${pkgname}" "cache_pkgnames: ${originspec} has no PKGNAME?"
	hash_set originspec-pkgname "${originspec}" "${pkgname}"
	hash_set originspec-pkgname "${flavor_originspec}" "${pkgname}"
	if [ -n "${port_flavor}" ]; then
		hash_set originspec-flavor "${originspec}" "${port_flavor}"
	fi
	hash_set pkgname-originspec "${pkgname}" "${originspec}"
	hash_set originspec-deps "${originspec}" "${pdeps}"
	hash_set originspec-ignore "${originspec}" "${ignore}"
	# Record all known packages for comparing to the queue later.
	ALL_PKGNAMES="${ALL_PKGNAMES}${ALL_PKGNAMES:+ }${pkgname}"
	ALL_ORIGINS="${ALL_ORIGINS}${ALL_ORIGINS:+ }${originspec}"
	was_listed_with_flavor=0
	if [ -n "${flavors}" ]; then
		default_flavor="${flavors%% *}"
		if [ "${ALL:-0}" -eq 1 ]; then
			was_listed_with_flavor=1
		else
			case " ${LISTPORTS} " in
			*" ${originspec} "*)
				;;
			*" ${origin}@${port_flavor-null} "*|\
			*" ${origin}@${FLAVOR_ALL-null} "*)
				was_listed_with_flavor=1
				;;
			esac
		fi
	fi
	if [ -z "${ignore}" ]; then
		for dep_origin in ${pdeps}; do
			if cache_pkgnames 1 "${dep_origin}"; then
				if [ "${was_listed_with_flavor}" -eq 1 ]; then
					continue
				fi
			fi
		done
	fi
	# Also cache all of the FLAVOR deps/PKGNAMES
	if [ "${isdep}" -eq "0" -o "${ALL:-0}" -eq 1 ] &&
		[ -n "${flavors}" ] &&
		[ "${spec_flavor}" = "${FLAVOR_ALL:-null}" -o \
		"${ALL:-0}" -eq 1 -o "${FLAVOR_DEFAULT_ALL:-}" = "yes" ]; then
		default_flavor="${flavors%% *}"
		for flavor in ${flavors}; do
			# Don't recurse on the first flavor since we are it.
			[ "${flavor}" = "${default_flavor}" ] && continue
			originspec_encode flavor_originspec "${origin}" "${flavor}" "${subpkg}"
			cache_pkgnames 0 "${flavor_originspec}" || :
		done
	fi

	[ -n "${ignore}" ]
}

expand_origin_flavors() {
	local origins="$1"
	local var_return="$2"
	local originspec origin flavor flavors _expanded subpkg

	_expanded=
	for originspec in ${origins}; do
		originspec_decode "${originspec}" origin flavor subpkg
		hash_get origin-flavors "${origin}" flavors || flavors=
		if [ -n "${flavor}" -a "${flavor}" != "${FLAVOR_ALL}" ] || \
		    [ -z "${flavors}" ] || \
		    [ "${FLAVOR_DEFAULT_ALL}" != "yes" -a \
		    ${ALL} -eq 0 -a \
		    "${flavor}" != "${FLAVOR_ALL}" ]; then
			_expanded="${_expanded:+${_expanded} }${originspec}"
			continue
		fi
		# Add all FLAVORS in for this one
		for flavor in ${flavors}; do
			originspec_encode originspec "${origin}" "${flavor}" "${subpkg}"
			_expanded="${_expanded:+${_expanded} }${originspec}"
		done
	done

	setvar "${var_return}" "${_expanded}"
}

list_all_deps() {
	local origins="$1"
	local var_return="$2"
	local originspec origin _out flavors deps subpkg
	local dep_originspec dep_origin dep_flavor dep_flavors dep_subpkg
	local dep_default_flavor
	# Don't list 'recursed' local or setvar won't work to parent

	[ "${var_return}" = recursed ] || _out=

	for originspec in ${origins}; do
		# If it's already in the list, nothing to do
		case " ${_out} " in
			*\ ${originspec}\ *) continue ;;
		esac
		_out="${_out:+${_out} }${originspec}"
		originspec_decode "${originspec}" origin flavor subpkg
		flavors=
		[ -z "${flavor}" ] && \
		    hash_get origin-flavors "${origin}" flavors
		fix_default_flavor "${originspec}" originspec
		# Check all deps
		hash_get originspec-deps "${originspec}" deps || deps=
		for dep_originspec in ${deps}; do
			# If the dependency has flavors and is not
			# FLAVOR-specific, it needs to be changed to
			# depend on the default FLAVOR instead.
			originspec_decode "${dep_originspec}" dep_origin \
			    dep_flavor dep_subpkg
			if [ -z "${dep_flavor}" ]; then
				hash_get origin-flavors \
				    "${dep_origin}" dep_flavors || \
				    dep_flavors=
				if [ -n "${dep_flavors}" ]; then
					# Change to default
					dep_default_flavor="${dep_flavors%% *}"
					dep_flavor="${dep_default_flavor}"
					originspec_encode dep_originspec \
					    "${dep_origin}" "${dep_flavor}" "${dep_subpkg}"
				fi
			fi

			recursed=
			list_all_deps "${dep_originspec}" recursed
			_out="${recursed}"
		done
		# And all FLAVORS if needed
		if [ -n "${flavor}" ]; then
			orig_originspec="${originspec}"
			for flavor in ${flavors}; do
				originspec_encode originspec "${origin}" \
				    "${flavor}" "${subpkg}"
				recursed=
				list_all_deps "${originspec}" recursed
				_out="${recursed}"
			done
		fi
	done
	_out="${_out# }"
	_out="${_out% }"
	setvar "${var_return}" "${_out}"
}

assert_queued() {
	local dep="$1"
	local origins="$2"
	local tmp originspec origins_expanded

	if [ ! -f "${log}/.poudriere.ports.queued" ]; then
		[ -z "${origins-}" ] && return 0
		err 1 ".poudriere.ports.queued file is missing while EXPECTED_QUEUED${dep:+(${dep})} is: ${origins}"
	fi

	tmp="$(mktemp -t queued.${dep})"
	awk -v dep="${dep}" '$3 == dep' "${log}/.poudriere.ports.queued" \
	    > "${tmp}"
	# First fix the list to expand main port FLAVORS
	expand_origin_flavors "${origins}" origins_expanded
	# The queue does remove duplicates - do the same here
	origins_expanded="$(echo "${origins_expanded}" | tr ' ' '\n' | sort -u | paste -s -d ' ' -)"
	echo "Asserting that only '${origins_expanded}' are in the${dep:+ ${dep}} queue"
	for originspec in ${origins_expanded}; do
		fix_default_flavor "${originspec}" originspec
		hash_get originspec-pkgname "${originspec}" pkgname
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec} (is this pkg actually expected here?)"
		echo "=> Asserting that ${originspec} | ${pkgname} is${dep:+ dep=${dep}} in queue"
		awk -vpkgname="${pkgname}" -voriginspec="${originspec}" -vdep="${dep}" '
		    $1 == originspec && $2 == pkgname && (dep == "" || $3 == dep) {
			print "==> " $0
			if (found == 1) {
				# A duplicate, no good.
				found = 0
				exit 1
			}
			found = 1
			next
		    }
		    $1 == originspec && $2 == pkgname && dep != "" && $3 != dep {
			print "==> " $0
			found = 0
			exit 1
		    }
		    END { if (found != 1) exit 1 }
		' ${log}/.poudriere.ports.queued >&2
		assert 0 $? "${originspec} | ${pkgname} should be queued${dep:+ with dep=${dep}}"
		# Remove the entry so we can assert later that nothing extra
		# is in the queue.
		cat "${tmp}" | \
		    awk -vpkgname="${pkgname}" -voriginspec="${originspec}" \
		    -vdep="${dep}" '
		    $1 == originspec && $2 == pkgname && $3 == dep { next }
		    { print }
		' > "${tmp}.new"
		mv -f "${tmp}.new" "${tmp}"
	done
	echo "=> Asserting that nothing else is in the${dep:+ ${dep}} queue"
	cat "${tmp}" | sed -e 's,^,==> ,' >&2
	! [ -s "${tmp}" ]
	assert 0 $? "Queue${dep:+(${dep})} should be empty"
	rm -f "${tmp}"
}

assert_ignored() {
	local origins="$1"
	local tmp originspec origins_expanded

	if [ ! -f "${log}/.poudriere.ports.ignored" ]; then
		[ -z "${origins-}" ] && return 0
		err 1 ".poudriere.ports.ignored file is missing while EXPECTED_IGNORED is: ${origins}"
	fi

	tmp="$(mktemp -t queued)"
	cp -f "${log}/.poudriere.ports.ignored" "${tmp}"
	# First fix the list to expand main port FLAVORS
	expand_origin_flavors "${origins}" origins_expanded
	# The queue does remove duplicates - do the same here
	origins_expanded="$(echo "${origins_expanded}" | tr ' ' '\n' | sort -u | paste -s -d ' ' -)"
	echo "Asserting that only '${origins_expanded}' are in the ignored list"
	for originspec in ${origins_expanded}; do
		fix_default_flavor "${originspec}" originspec
		hash_get originspec-pkgname "${originspec}" pkgname
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec} (is this pkg actually expected here?)"
		echo "=> Asserting that ${originspec} | ${pkgname} is ignored"
		awk -vpkgname="${pkgname}" -voriginspec="${originspec}" '
		    $1 == originspec && $2 == pkgname && ($3 != "") {
			print "==> " $0
			if (found == 1) {
				# A duplicate, no good.
				found = 0
				exit 1
			}
			found = 1
			next
		    }
		    END { if (found != 1) exit 1 }
		' ${log}/.poudriere.ports.ignored >&2
		assert 0 $? "${originspec} | ${pkgname} should be ignored"
		# Remove the entry so we can assert later that nothing extra
		# is in the queue.
		cat "${tmp}" | \
		    awk -vpkgname="${pkgname}" -voriginspec="${originspec}" '
		    $1 == originspec && $2 == pkgname && $3 != "" { next }
		    { print }
		' > "${tmp}.new"
		mv -f "${tmp}.new" "${tmp}"
	done
	echo "=> Asserting that nothing else is ignored"
	cat "${tmp}" | sed -e 's,^,==> ,' >&2
	! [ -s "${tmp}" ]
	assert 0 $? "Ignore list should be empty"
	rm -f "${tmp}"
}

assert_skipped() {
	local origins="$1"
	local tmp originspec origins_expanded

	if [ ! -f "${log}/.poudriere.ports.skipped" ]; then
		[ -z "${origins-}" ] && return 0
		err 1 ".poudriere.ports.skipped file is missing while EXPECTED_SKIPPED is: ${origins}"
	fi

	tmp="$(mktemp -t queued)"
	cp -f "${log}/.poudriere.ports.skipped" "${tmp}"
	# First fix the list to expand main port FLAVORS
	expand_origin_flavors "${origins}" origins_expanded
	# The queue does remove duplicates - do the same here
	origins_expanded="$(echo "${origins_expanded}" | tr ' ' '\n' | sort -u | paste -s -d ' ' -)"
	echo "Asserting that only '${origins_expanded}' are in the skipped list"
	for originspec in ${origins_expanded}; do
		#fix_default_flavor "${originspec}" originspec
		hash_get originspec-pkgname "${originspec}" pkgname
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec} (is this pkg actually expected here?)"
		echo "=> Asserting that ${originspec} | ${pkgname} is skipped"
		awk -vpkgname="${pkgname}" -voriginspec="${originspec}" '
		    $1 == originspec && $2 == pkgname {
			print "==> " $0
			if (found == 1) {
				# A duplicate, no good.
				found = 0
				exit 1
			}
			found = 1
			next
		    }
		    END { if (found != 1) exit 1 }
		' ${log}/.poudriere.ports.skipped >&2
		assert 0 $? "${originspec} | ${pkgname} should be skipped"
		# Remove the entry so we can assert later that nothing extra
		# is in the queue.
		cat "${tmp}" | \
		    awk -vpkgname="${pkgname}" -voriginspec="${originspec}" '
		    $1 == originspec && $2 == pkgname { next }
		    { print }
		' > "${tmp}.new"
		mv -f "${tmp}.new" "${tmp}"
	done
	echo "=> Asserting that nothing else is skipped"
	cat "${tmp}" | sed -e 's,^,==> ,' >&2
	! [ -s "${tmp}" ]
	assert 0 $? "Skipped list should be empty"
	rm -f "${tmp}"
}

assert_counts() {
	local queued expected_queued ignored expected_ignored
	local skipped expected_skipped

	if [ -z "${EXPECTED_QUEUED-}" ]; then
		expected_queued=0
	else
		expected_queued=$(echo "${EXPECTED_QUEUED}" | tr ' ' '\n' | wc -l)
		expected_queued="${expected_queued##* }"
	fi
	if [ -z "${EXPECTED_IGNORED-}" ]; then
		expected_ignored=0
	else
		expected_ignored=$(echo "${EXPECTED_IGNORED}" | tr ' ' '\n' | wc -l)
		expected_ignored="${expected_ignored##* }"
	fi
	if [ -z "${EXPECTED_SKIPPED-}" ]; then
		expected_skipped=0
	else
		expected_skipped=$(echo "${EXPECTED_SKIPPED}" | tr ' ' '\n' | wc -l)
		expected_skipped="${expected_skipped##* }"
	fi
	expected_queued=$((expected_queued + expected_ignored + expected_skipped))
	echo "=> Asserting queued=${expected_queued} ignored=${expected_ignored} skipped=${expected_skipped}"

	read queued < "${log}/.poudriere.stats_queued"
	assert 0 $? "${log}/.poudriere.stats_queued read should pass"
	assert "${expected_queued}" "${queued}" "queued should match"

	if [ -n "${EXPECTED_IGNORED-}" ]; then
		read ignored < "${log}/.poudriere.stats_ignored"
		assert 0 $? "${log}/.poudriere.stats_ignored read should pass"
	else
		ignored=0
	fi
	assert "${expected_ignored}" "${ignored}" "ignored should match"

	if [ -n "${EXPECTED_SKIPPED-}" ]; then
		read skipped < "${log}/.poudriere.stats_skipped"
		assert 0 $? "${log}/.poudriere.stats_skipped read should pass"
	else
		skipped=0
	fi
	assert "${expected_skipped}" "${skipped}" "skipped should match"
}

do_bulk() {
	local verbose n
	local -;set -v

	n=0
	until [ "${n}" -eq "${VERBOSE}" ]; do
		[ -z "${verbose}" ] && verbose=-
		verbose="${verbose}v"
		n=$((n + 1))
	done
	${SUDO} ${POUDRIEREPATH} -e ${POUDRIERE_ETC} bulk -CNt ${verbose} \
	    ${OVERLAYS:+$(echo "${OVERLAYS}" | tr ' ' '\n' | sed -e 's,^,-O ,' | paste -d ' ' -s -)} \
	    ${JFLAG:+-J ${JFLAG}} \
	    -B "${BUILDNAME}" \
	    -j "${JAILNAME}" -p "${PTNAME}" ${SETNAME:+-z "${SETNAME}"} \
	    "$@"
}

sorted() {
	if [ "$#" -eq 0 ]; then
		echo
		return 0
	fi
	echo "$@" | tr ' ' '\n' | LC_ALL=C sort | paste -s -d ' ' -
}

assert_bulk_queue_and_stats() {
	local expanded_LISTPORTS_NOIGNORED
	local port
	local -

	# FIXME: had to comment out set -u, as it was making all tests fail
	#set -u
	### Now do tests against the output of the bulk run. ###

	# Assert that only listed packages are in poudriere.ports.queued as
	# 'listed'
	if [ -z "${EXPECTED_LISTED-}" ]; then
		# compat for tests
		if [ -z "${EXPECTED_QUEUED-null}" ]; then
			EXPECTED_LISTED=
		else
			EXPECTED_LISTED="${LISTPORTS}"
		fi
	fi
	assert_queued "listed" "${EXPECTED_LISTED-}"

	# Assert the IGNOREd ports are tracked in .poudriere.ports.ignored
	assert_ignored "${EXPECTED_IGNORED-}"

	# Assert that SKIPPED ports are right
	assert_skipped "${EXPECTED_SKIPPED-}"

	# Assert that all expected dependencies are in poudriere.ports.queued
	# (since they do not exist yet)
	assert_queued "" "${EXPECTED_QUEUED-}"

	# Assert stats counts are right
	assert_counts
}

assert_bulk_build_results() {
	local pkgname file log originspec origin flavor flavor2 subpkg
	local PKG_BIN pkg_originspec pkg_origin pkg_flavor

	: ${LOCALBASE:=/usr/local}
	: ${PKG_BIN:=${LOCALBASE}/sbin/pkg-static}

	which -s "${PKG_BIN}" || err 99 "Unable to find in host: ${PKG_BIN}"
	_log_path log || err 99 "Unable to determine logdir"

	[ -d "${PACKAGES}" ]
	assert 0 $? "PACKAGES directory should exist: ${PACKAGES}"

	echo "Asserting that packages were built"
	for pkgname in ${ALL_PKGNAMES}; do
		file="${PACKAGES}/All/${pkgname}${P_PKG_SUFX}"
		[ -f "${file}" ]
		assert 0 $? "Package should exist: ${file}"
		[ -s "${file}" ]
		assert 0 $? "Package should not be empty: ${file}"
	done

	echo "Asserting that logfiles were produced"
	for pkgname in ${ALL_PKGNAMES}; do
		file="${log}/logs/${pkgname}.log"
		[ -f "${file}" ]
		assert 0 $? "Logfile should exist: ${file}"
		[ -s "${file}" ]
		assert 0 $? "Logfile should not be empty: ${file}"
	done

	echo "Asserting package metadata sanity check"
	for pkgname in ${ALL_PKGNAMES}; do
		file="${PACKAGES}/All/${pkgname}${P_PKG_SUFX}"
		hash_get pkgname-originspec "${pkgname}" originspec ||
			err 99 "Unable to find originspec for pkgname: ${pkgname}"
		# Restore default flavor
		originspec_decode "${originspec}" origin flavor subpkg
		if [ -z "${flavor}" ] &&
			hash_get originspec_flavor "${originspec}" flavor; then
			originspec_encode originspec "${origin}" \
				"${flavor}" "${subpkg}"
		fi
		pkg_origin=$(${PKG_BIN} query -F "${file}" '%o')
		assert 0 $? "Unable to get origin from package: ${file}"
		assert "${origin}" "${pkg_origin}" "Package origin should match for: ${file}"

		pkg_flavor=$(${PKG_BIN} query -F "${file}" '%At %Av' |
			awk '$1 == "flavor" {print $2}')
		assert 0 $? "Unable to get flavor from package: ${file}"
		assert "${flavor}" "${pkg_flavor}" "Package flavor should match for: ${file}"
	done

}

SUDO=
if [ $(id -u) -ne 0 ]; then
	if ! which sudo >/dev/null 2>&1; then
		echo "SKIP: Need root or sudo access for bulk tests" >&2
		exit 77
	fi
	SUDO="sudo"
fi

if [ -z "${POUDRIEREPATH}" ]; then
	echo "ERROR: Unable to determine poudriere" >&2
	exit 99
fi

: ${SCRIPTNAME:=${0%.sh}}
SCRIPTNAME="${SCRIPTNAME##*/}"
BUILDNAME="$(date +%s)"
POUDRIERE="${POUDRIEREPATH} -e ${POUDRIERE_ETC}"
ARCH=$(uname -p)
JAILNAME="poudriere-test-${ARCH}"
JAIL_VERSION="12.4-RELEASE"
JAILMNT=$(${POUDRIERE} api "jget ${JAILNAME} mnt" || echo)
export UNAME_r=$(freebsd-version)
export UNAME_v="FreeBSD ${UNAME_r}"
if [ -z "${JAILMNT}" ]; then
	if [ ${BOOTSTRAP_ONLY:-0} -eq 0 ]; then
		echo "ERROR: Must run prep.sh" >&2
		exit 99
	fi
	echo "Setting up jail for testing..." >&2
	if ! ${SUDO} ${POUDRIERE} jail -c -j "${JAILNAME}" \
	    -v "${JAIL_VERSION}" -a "$(uname -m).${ARCH}"; then
		echo "SKIP: Cannot setup jail with Poudriere" >&2
		exit 77
	fi
	JAILMNT=$(${POUDRIERE} api "jget ${JAILNAME} mnt" || echo)
	if [ -z "${JAILMNT}" ]; then
		echo "SKIP: Failed fetching mnt for new jail in Poudriere" >&2
		exit 77
	fi
	echo "Done setting up test jail" >&2
	echo >&2
fi
if [ ${BOOTSTRAP_ONLY:-0} -eq 1 ]; then
	exit 0
fi

if [ ${ALL:-0} -eq 0 ]; then
	assert_not "" "${LISTPORTS}" "LISTPORTS empty"
fi

: ${PORTSDIR:=${THISDIR%/*}/test-ports/default}
export PORTSDIR
PTMNT="${PORTSDIR}"
#: ${PTNAME:=${PTMNT##*/}}
: ${PTNAME:=$(echo "${PORTSDIR}" | tr '[./]' '_')}
: ${SETNAME:=${SCRIPTNAME}}
export PORT_DBDIR=/dev/null
export __MAKE_CONF="${POUDRIERE_ETC}/poudriere.d/make.conf"
export SRCCONF=/dev/null
export SRC_ENV_CONF=/dev/null
export PACKAGE_BUILDING=yes

write_atomic_cmp "${POUDRIERE_ETC}/poudriere.d/${SETNAME}-poudriere.conf" << EOF
${FLAVOR_DEFAULT_ALL:+FLAVOR_DEFAULT_ALL=${FLAVOR_DEFAULT_ALL}}
${FLAVOR_ALL:+FLAVOR_ALL=${FLAVOR_ALL}}
${IMMUTABLE_BASE:+IMMUTABLE_BASE=${IMMUTABLE_BASE}}
EOF

. ${SCRIPTPREFIX}/common.sh

echo -n "Pruning stale jails..."
${SUDO} ${POUDRIEREPATH} -e ${POUDRIERE_ETC} jail -k \
    -j "${JAILNAME}" -p "${PTNAME}" ${SETNAME:+-z "${SETNAME}"} \
    >/dev/null || :
echo " done"
echo -n "Pruning previous logs..."
${SUDO} ${POUDRIEREPATH} -e ${POUDRIERE_ETC} logclean \
    -j "${JAILNAME}" -p "${PTNAME}" ${SETNAME:+-z "${SETNAME}"} \
    -ay >/dev/null || :
echo " done"

# Import local ports tree
pset "${PTNAME}" mnt "${PTMNT}"
pset "${PTNAME}" method "-"

MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
_mastermnt MASTERMNT
export POUDRIERE_BUILD_TYPE=bulk
_log_path log
: ${PACKAGES:=${POUDRIERE_DATA}/packages/${MASTERNAME}}

# Setup basic overlay to test-ports/overlay/ dir.
OVERLAYSDIR="$(mktemp -ut overlays)"
OVERLAYS_save="${OVERLAYS}"
OVERLAYS=
for o in ${OVERLAYS_save}; do
	omnt="${PTMNT%/*}/${o}"
	[ -d "${omnt}" ] || continue
	#oname=$(echo "${omnt}" | tr '[./]' '_')
	# <12 still has 88 mount path restrictions
	oname="$(stat -f %i "${omnt}")_${o}"
	pset "${oname}" mnt "${omnt}"
	pset "${oname}" method "-"
	# We run port_var_fetch_originspec without a jail so can't use plain
	# /overlays. Need to link the host path into our fake MASTERMNT path
	# as well as link to the overlay portdir without nullfs.
	mkdir -p "${MASTERMNT:?}/${OVERLAYSDIR%/*}"
	ln -fs "${MASTERMNT}/${OVERLAYSDIR}" "${OVERLAYSDIR}"
	mkdir -p "${MASTERMNT}/${OVERLAYSDIR}"
	ln -fs "${omnt}" "${MASTERMNT:?}/${OVERLAYSDIR}/${oname}"
	OVERLAYS="${OVERLAYS:+${OVERLAYS} }${oname}"
done
unset OVERLAYS_save omnt oname

ALL_PKGNAMES=
ALL_ORIGINS=
if [ ${ALL} -eq 1 ]; then
	LISTPORTS="$(listed_ports | paste -s -d ' ' -)"
fi
LISTPORTS="$(sorted "${LISTPORTS}")"
if [ "${FLAVOR_DEFAULT_ALL-null}" == "yes" ]; then
	LISTPORTS="$(echo "${LISTPORTS}" | tr ' ' '\n' |
	    sed -e 's,$,@all,' | paste -s -d ' ' -)"
fi
echo -n "Gathering metadata for requested ports..."
for origin in ${LISTPORTS}; do
	cache_pkgnames 0 "${origin}" || :
done
echo " done"
expand_origin_flavors "${LISTPORTS}" LISTPORTS_EXPANDED
fetch_global_port_vars || err 99 "Unable to fetch port vars"
assert_not "null" "${P_PORTS_FEATURES-null}" "fetch_global_port_vars should work"
echo "Building: $(echo ${LISTPORTS_EXPANDED})"
set +e
