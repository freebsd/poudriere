# Common setup for bulk test runs
: ${ALL:=0}

# Strip away @DEFAULT if it is the default FLAVOR
fix_default_flavor() {
	local _originspec="$1"
	local var_return="$2"
	local _origin _flavor _flavors _default_flavor

	originspec_decode "${_originspec}" _origin '' _flavor
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
	local originspec="$1"
	local origin dep_origin flavor flavors pkgname default_flavor ignore
	local flavor_originspec ret

	if hash_get originspec-pkgname "${originspec}" pkgname; then
		hash_get originspec-ignore "${originspec}" ignore
		ret=1
		[ -n "${ignore}" ] && ret=0
		return ${ret}
	fi

	originspec_decode "${originspec}" origin '' flavor

	if [ "${flavor}" = "${FLAVOR_DEFAULT}" ]; then
		originspec_encode originspec "${origin}" '' ''
	elif [ "${flavor}" = "${FLAVOR_ALL}" ]; then
		unset flavor
		originspec_encode originspec "${origin}" '' ''
	fi

	port_var_fetch_originspec "${originspec}" \
	   PKGNAME pkgname \
	   FLAVORS flavors \
	   IGNORE ignore \
	    _PDEPS='${PKG_DEPENDS} ${EXTRACT_DEPENDS} ${PATCH_DEPENDS} ${FETCH_DEPENDS} ${BUILD_DEPENDS} ${LIB_DEPENDS} ${RUN_DEPENDS}' \
	    '${_PDEPS:C,([^:]*):([^:]*):?.*,\2,:C,^${PORTSDIR}/,,:O:u}' \
	    pdeps
	hash_set origin-flavors "${origin}" "${flavors}"
	fix_default_flavor "${originspec}" originspec
	hash_set originspec-pkgname "${originspec}" "${pkgname}"
	hash_set originspec-deps "${originspec}" "${pdeps}"
	hash_set originspec-ignore "${originspec}" "${ignore}"
	# Record all known packages for comparing to the queue later.
	ALL_PKGNAMES="${ALL_PKGNAMES}${ALL_PKGNAMES:+ }${pkgname}"
	ALL_ORIGINS="${ALL_ORIGINS}${ALL_ORIGINS:+ }${originspec}"
	[ -n "${ignore}" ] && list_add IGNOREDPORTS "${originspec}"
	for dep_origin in ${pdeps}; do
		if cache_pkgnames "${dep_origin}"; then
			if ! list_contains SKIPPEDPORTS "${originspec}"; then
				list_add SKIPPEDPORTS "${originspec}"
			fi
		fi
	done
	# Also cache all of the FLAVOR deps/PKGNAMES
	if [ -n "${flavor}" ]; then
		default_flavor="${flavors%% *}"
		for flavor in ${flavors}; do
			# Don't recurse on the first flavor since we are it.
			[ "${flavor}" = "${default_flavor}" ] && continue
			originspec_encode flavor_originspec "${origin}" '' "${flavor}"
			cache_pkgnames "${flavor_originspec}" || :
		done
	fi

	[ -n "${ignore}" ]
}

expand_origin_flavors() {
	local origins="$1"
	local var_return="$2"
	local originspec origin flavor flavors _expanded

	for originspec in ${origins}; do
		originspec_decode "${originspec}" origin '' flavor
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
			originspec_encode originspec "${origin}" '' "${flavor}"
			_expanded="${_expanded:+${_expanded} }${originspec}"
		done
	done

	setvar "${var_return}" "${_expanded}"
}

list_all_deps() {
	local origins="$1"
	local var_return="$2"
	local originspec origin _out flavors deps
	local dep_originspec dep_origin dep_flavor dep_flavors
	local dep_default_flavor
	# Don't list 'recursed' local or setvar won't work to parent

	[ "${var_return}" = recursed ] || _out=

	for originspec in ${origins}; do
		# If it's already in the list, nothing to do
		case " ${_out} " in
			*\ ${originspec}\ *) continue ;;
		esac
		_out="${_out:+${_out} }${originspec}"
		originspec_decode "${originspec}" origin '' flavor
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
			    '' dep_flavor
			if [ -z "${dep_flavor}" ]; then
				hash_get origin-flavors \
				    "${dep_origin}" dep_flavors || \
				    dep_flavors=
				if [ -n "${dep_flavors}" ]; then
					# Change to default
					dep_default_flavor="${dep_flavors%% *}"
					dep_flavor="${dep_default_flavor}"
					originspec_encode dep_originspec \
					    "${dep_origin}" '' "${dep_flavor}"
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
				originspec_encode originspec "${origin}" '' \
				    "${flavor}"
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
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec}"
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
	assert 0 $? "Queue should be empty"
	rm -f "${tmp}"
}

assert_ignored() {
	local origins="$1"
	local tmp originspec origins_expanded

	tmp="$(mktemp -t queued.${dep})"
	cp -f "${log}/.poudriere.ports.ignored" "${tmp}"
	# First fix the list to expand main port FLAVORS
	expand_origin_flavors "${origins}" origins_expanded
	# The queue does remove duplicates - do the same here
	origins_expanded="$(echo "${origins_expanded}" | tr ' ' '\n' | sort -u | paste -s -d ' ' -)"
	echo "Asserting that only '${origins_expanded}' are in the ignored list"
	for originspec in ${origins_expanded}; do
		fix_default_flavor "${originspec}" originspec
		hash_get originspec-pkgname "${originspec}" pkgname
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec}"
		echo "=> Asserting that ${originspec} | ${pkgname} is ignored"
		awk -vpkgname="${pkgname}" -voriginspec="${originspec}" '
		    $1 == originspec && $2 == pkgname && ($3 == "ignored") {
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
		    $1 == originspec && $2 == pkgname && $3 == "ignored" { next }
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

	tmp="$(mktemp -t queued.${dep})"
	cp -f "${log}/.poudriere.ports.skipped" "${tmp}"
	# First fix the list to expand main port FLAVORS
	expand_origin_flavors "${origins}" origins_expanded
	# The queue does remove duplicates - do the same here
	origins_expanded="$(echo "${origins_expanded}" | tr ' ' '\n' | sort -u | paste -s -d ' ' -)"
	echo "Asserting that only '${origins_expanded}' are in the skipped list"
	for originspec in ${origins_expanded}; do
		fix_default_flavor "${originspec}" originspec
		hash_get originspec-pkgname "${originspec}" pkgname
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec}"
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

	if [ -z "${ALL_EXPECTED}" ]; then
		expected_queued=0
	else
		expected_queued=$(echo "${ALL_EXPECTED}" | tr ' ' '\n' | wc -l)
		expected_queued="${expected_queued##* }"
	fi
	if [ -z "${IGNOREDPORTS}" ]; then
		expected_ignored=0
	else
		expected_ignored=$(echo "${IGNOREDPORTS}" | tr ' ' '\n' | wc -l)
		expected_ignored="${expected_ignored##* }"
	fi
	if [ -z "${SKIPPEDPORTS}" ]; then
		expected_skipped=0
	else
		expected_skipped=$(echo "${SKIPPEDPORTS}" | tr ' ' '\n' | wc -l)
		expected_skipped="${expected_skipped##* }"
	fi
	expected_queued=$((expected_queued + expected_ignored + expected_skipped))
	echo "=> Asserting queued=${expected_queued} ignored=${expected_ignored} skipped=${expected_skipped}"

	read queued < "${log}/.poudriere.stats_queued"
	assert 0 $? "${log}/.poudriere.stats_queued read should pass"
	assert "${expected_queued}" "${queued}" "queued should match"

	read ignored < "${log}/.poudriere.stats_ignored"
	assert 0 $? "${log}/.poudriere.stats_ignored read should pass"
	assert "${expected_ignored}" "${ignored}" "ignored should match"

	read skipped < "${log}/.poudriere.stats_skipped"
	assert 0 $? "${log}/.poudriere.stats_skipped read should pass"
	assert "${expected_skipped}" "${skipped}" "skipped should match"
}

# Avoid injail() for port_var_fetch
INJAIL_HOST=1

. common.sh

SUDO=
if [ $(id -u) -ne 0 ]; then
	if ! which sudo >/dev/null 2>&1; then
		echo "SKIP: Need root or sudo access for bulk tests" >&2
		exit 1
	fi
	SUDO="sudo"
fi

: ${SCRIPTNAME:=${0%.sh}}
SCRIPTNAME="${SCRIPTNAME##*/}"
BUILDNAME="bulk"
POUDRIERE="${POUDRIEREPATH} -e ${POUDRIERE_ETC}"
ARCH=$(uname -p)
JAILNAME="poudriere-test-${ARCH}$(echo "${THISDIR}" | tr '/' '_')"
JAIL_VERSION="11.3-RELEASE"
JAILMNT=$(${POUDRIERE} api "jget ${JAILNAME} mnt" || echo)
export UNAME_r=$(freebsd-version)
export UNAME_v="FreeBSD $(freebsd-version)"
if [ -z "${JAILMNT}" ]; then
	echo "Setting up jail for testing..." >&2
	if ! ${SUDO} ${POUDRIERE} jail -c -j "${JAILNAME}" \
	    -v "${JAIL_VERSION}" -a ${ARCH}; then
		echo "SKIP: Cannot setup jail with Poudriere" >&2
		exit 1
	fi
	JAILMNT=$(${POUDRIERE} api "jget ${JAILNAME} mnt" || echo)
	if [ -z "${JAILMNT}" ]; then
		echo "SKIP: Failed fetching mnt for new jail in Poudriere" >&2
		exit 1
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

. ${SCRIPTPREFIX}/common.sh

: ${PORTSDIR:=${THISDIR}/../test-ports/default}
export PORTSDIR
PTMNT="${PORTSDIR}"
: ${PTNAME:=${PTMNT##*/}}
: ${SETNAME:=${SCRIPTNAME}}
export PORT_DBDIR=/dev/null
export __MAKE_CONF="${POUDRIERE_ETC}/poudriere.d/make.conf"
export SRCCONF=/dev/null
export SRC_ENV_CONF=/dev/null

cat > "${POUDRIERE_ETC}/poudriere.d/${SETNAME}-poudriere.conf" << EOF
${FLAVOR_DEFAULT_ALL:+FLAVOR_DEFAULT_ALL=${FLAVOR_DEFAULT_ALL}}
${FLAVOR_ALL:+FLAVOR_ALL=${FLAVOR_ALL}}
EOF

echo -n "Pruning stale jails..."
${SUDO} ${POUDRIEREPATH} -e ${POUDRIERE_ETC} jail -k \
    -j "${JAILNAME}" -p "${PTNAME}" ${SETNAME:+-z "${SETNAME}"} \
    >/dev/null || :
echo " done"
echo -n "Pruning previous logs..."
${SUDO} ${POUDRIEREPATH} -e ${POUDRIERE_ETC} logclean \
    -B "${BUILDNAME}" \
    -j "${JAILNAME}" -p "${PTNAME}" ${SETNAME:+-z "${SETNAME}"} \
    -ay >/dev/null || :
echo " done"

set -e

# Import local ports tree
pset "${PTNAME}" mnt "${PTMNT}"
pset "${PTNAME}" method "-"

MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
_mastermnt MASTERMNT
export POUDRIERE_BUILD_TYPE=bulk
_log_path log

# Setup basic overlay to test-ports/overlay/ dir.
for o in ${OVERLAYS}; do
	[ -d "${PTMNT%/*}/${o}" ] || continue
	pset "${o}" mnt "${PTMNT%/*}/${o}"
	pset "${o}" method "-"
	# We run port_var_fetch_originspec without a jail so can't use plain
	# /overlays. Need to link the host path into our fake MASTERMNT path
	# as well as link to the overlay portdir without nullfs.
	OVERLAYSDIR="$(mktemp -ut overlays)"
	mkdir -p "${MASTERMNT}/${OVERLAYSDIR%/*}"
	ln -fs "${MASTERMNT}/${OVERLAYSDIR}" "${OVERLAYSDIR}"
	mkdir -p "${MASTERMNT}/${OVERLAYSDIR}"
	ln -fs "${PTMNT%/*}/${o}" "${MASTERMNT}/${OVERLAYSDIR}/${o}"
done

set +e

ALL_PKGNAMES=
ALL_ORIGINS=
if [ ${ALL} -eq 1 ]; then
	LISTPORTS="$(listed_ports | paste -s -d ' ' -)"
fi
echo -n "Gathering metadata for requested ports..."
IGNOREDPORTS=""
SKIPPEDPORTS=""
for origin in ${LISTPORTS}; do
	cache_pkgnames "${origin}" || :
done
echo " done"
expand_origin_flavors "${LISTPORTS}" LISTPORTS_EXPANDED
LISTPORTS_NOIGNORED="${LISTPORTS_EXPANDED}"
# Separate out IGNORED ports
if [ -n "${IGNOREDPORTS}" ]; then
	_IGNOREDPORTS="${IGNOREDPORTS}"
	for port in ${_IGNOREDPORTS}; do
		list_remove LISTPORTS_NOIGNORED "${port}"
		list_remove SKIPPEDPORTS "${port}"
	done
fi
# Separate out SKIPPED ports
if [ -n "${SKIPPEDPORTS}" ]; then
	_SKIPPEDPORTS="${SKIPPEDPORTS}"
	for port in ${_SKIPPEDPORTS}; do
		list_remove LISTPORTS_NOIGNORED "${port}"
	done
fi
echo "Building: $(echo ${LISTPORTS_EXPANDED})"
