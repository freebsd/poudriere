set -e
# Common setup for bulk test runs
: ${ALL:=0}
# Avoid injail() for port_var_fetch
INJAIL_HOST=1

: ${SCRIPTNAME:=${0}}

. ./common.sh

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

recache_pkgnames() {
	local var

	for var in \
	    origin-flavors \
	    originspec-deps \
	    originspec-ignore \
	    originspec-pkgname \
	    pkgname-originspec \
	    ; do
		hash_unset_var "${var}"
	done
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
	local OVERLAYS

	OVERLAYS="${REAL_OVERLAYS-}"
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

	# XXX: subpkg
	cleanenv port_var_fetch_originspec "${originspec}" \
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
		cleanenv port_var_fetch_originspec "${originspec_default}" \
		   PKGNAME pkgname_default \
		   FLAVORS flavors_default \
		   FLAVOR flavor_default || exit 99
		case "${flavors_default}" in
		"${flavor_default} "*|"${flavor_default}") ;;
		*)
			tmp="${flavor_default}"
			for x in ${flavors_default}; do
				case " ${tmp} " in
				*" ${x} "*) ;;
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
	hash_set pkgname-originspec "${pkgname}" "${flavor_originspec}"
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
	local IFS extra item
	local -; set +f

	_expanded=
	for item in ${origins}; do
		IFS=:
		set -- ${item}
		unset IFS
		originspec="$1"
		shift
		extra="$*"

		originspec_decode "${originspec}" origin flavor subpkg
		hash_get origin-flavors "${origin}" flavors || flavors=
		case "${flavor}" in
		""|"${FLAVOR_DEFAULT}")
			flavor="${flavors%% *}"
			originspec_encode originspec "${origin}" "${flavor}" \
			    "${subpkg}"
			;;
		esac
		if [ -n "${flavor}" -a "${flavor}" != "${FLAVOR_ALL}" ] || \
		    [ -z "${flavors}" ] || \
		    [ "${FLAVOR_DEFAULT_ALL}" != "yes" -a \
		    ${ALL} -eq 0 -a \
		    "${flavor}" != "${FLAVOR_ALL}" ]; then
			_expanded="${_expanded:+${_expanded} }${originspec}${extra:+:${extra}}"
			continue
		fi
		# Add all FLAVORS in for this one
		for flavor in ${flavors}; do
			originspec_encode originspec "${origin}" "${flavor}" \
			    "${subpkg}"
			_expanded="${_expanded:+${_expanded} }${originspec}${extra:+:${extra}}"
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

assert_metadata() {
	local dep="$1"
	local origins="$2"
	local tmp originspec origins_expanded

	if [ ! -f "${log:?}/.poudriere.all_pkgs%" ]; then
		[ -z "${origins-}" ] && return 0
		err 1 ".poudriere.all_pkgs% file is missing while checked list with dep='${dep}' is: ${origins}"
	fi

	tmp="$(mktemp -t metadata.${dep})"
	{ awk -v dep="${dep}" '$3 == dep' "${log}/.poudriere.all_pkgs%"; } \
	    > "${tmp}"
	# First fix the list to expand main port FLAVORS
	expand_origin_flavors "${origins}" origins_expanded
	origins_expanded="$(echo "${origins_expanded}" | tr ' ' '\n' | sort -u | paste -s -d ' ' -)"
	echo "Asserting that only '${origins_expanded}' are in the metadata with dep='${dep}'" >&2
	for originspec in ${origins_expanded}; do
		#fix_default_flavor "${originspec}" originspec
		hash_get originspec-pkgname "${originspec}" pkgname
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec} (is this pkg actually expected here?)"
		echo "=> Asserting that ${originspec} | ${pkgname} is dep='${dep}' in metadata" >&2
		{ awk -vpkgname="${pkgname}" -voriginspec="${originspec}" -vdep="${dep}" '
		    $2 == originspec && $1 == pkgname && $3 == dep {
			print "==> " $0
			if (found == 1) {
				# A duplicate, no good.
				found = 0
				exit 1
			}
			found = 1
			next
		    }
		    $2 == originspec && $1 == pkgname && dep != "" && $3 != dep {
			print "=!> " $0
			found = 0
			exit 1
		    }
		    END { if (found != 1) exit 1 }
		' ${log}/.poudriere.all_pkgs%; } >&2
		assert 0 $? "${originspec} | ${pkgname} should be known in metadata${dep:+ with dep=${dep}} in ${log}/.poudriere.all_pkgs%"
		# Remove the entry so we can assert later that nothing extra
		# is in the queue.
		{ awk -vpkgname="${pkgname}" -voriginspec="${originspec}" \
		    -vdep="${dep}" '
		    $2 == originspec && $1 == pkgname && $3 == dep { next }
		    { print }
		' "${tmp}"; } > "${tmp}.new"
		mv -f "${tmp}.new" "${tmp}"
	done
	echo "=> Asserting that nothing else is known in metadata with dep='${dep}'" >&2
	if [ -s "${tmp}" ]; then
		echo "=> Items remaining:" >&2
		{ sed -e 's,^,==> ,' "${tmp}"; } >&2
	fi
	! [ -s "${tmp}" ]
	assert 0 $? "Metadata${dep:+(${dep})} should be empty"
	rm -f "${tmp}"
}


assert_queued() {
	local dep="$1"
	local origins="$2"
	local tmp originspec origins_expanded
	local queuespec rdep

	if [ ! -f "${log:?}/.poudriere.ports.queued" ]; then
		[ -z "${origins-}" ] && return 0
		err 1 ".poudriere.ports.queued file is missing while EXPECTED_QUEUED${dep:+(${dep})} is: ${origins}"
	fi

	tmp="$(mktemp -t queued.${dep})"
	{ awk -v dep="${dep}" '(dep == "" || $3 == dep)' "${log}/.poudriere.ports.queued"; } \
	    > "${tmp}"
	# First fix the list to expand main port FLAVORS
	expand_origin_flavors "${origins}" origins_expanded
	# The queue does remove duplicates - do the same here
	origins_expanded="$(echo "${origins_expanded}" | tr ' ' '\n' | sort -u | paste -s -d ' ' -)"
	echo "Asserting that only '${origins_expanded}' are in the dep='${dep}' queue" >&2
	for queuespec in ${origins_expanded}; do
		case "${queuespec}" in
		*:*)
			originspec="${queuespec%:*}"
			rdep="${queuespec#*:}"
			;;
		*)
			originspec="${queuespec}"
			rdep=
		esac
		#fix_default_flavor "${originspec}" originspec
		hash_get originspec-pkgname "${originspec}" pkgname
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec} (is this pkg actually expected here?)"
		echo "=> Asserting that ${originspec} | ${pkgname} is dep='${dep}' in queue${rdep:+ with rdep ${rdep}}" >&2
		{ awk -vpkgname="${pkgname}" -voriginspec="${originspec}" -vdep="${dep:-${rdep}}" '
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
			print "=!> " $0
			found = 0
			exit 1
		    }
		    END { if (found != 1) exit 1 }
		' ${log}/.poudriere.ports.queued; } >&2
		assert 0 $? "${originspec} | ${pkgname} should be queued${dep:+ with dep=${dep}} in ${log}/.poudriere.ports.queued${rdep:+ with rdep ${rdep}}"
		# Remove the entry so we can assert later that nothing extra
		# is in the queue.
		{ awk -vpkgname="${pkgname}" -voriginspec="${originspec}" \
		    -vdep="${dep:-${rdep}}" '
		    $1 == originspec && $2 == pkgname && (dep == "" || $3 == dep) { next }
		    { print }
		' "${tmp}"; } > "${tmp}.new"
		mv -f "${tmp}.new" "${tmp}"
	done
	echo "=> Asserting that nothing else is in the dep='${dep}' queue" >&2
	if [ -s "${tmp}" ]; then
		echo "=> Items remaining:" >&2
		{ sed -e 's,^,==> ,' "${tmp}"; } >&2
	fi
	! [ -s "${tmp}" ]
	assert 0 $? "Queue${dep:+(${dep})} should be empty"
	rm -f "${tmp}"
}

assert_ignored() {
	local origins="$1"
	local tmp originspec origins_expanded ignorespec ignorereason

	if [ ! -f "${log:?}/.poudriere.ports.ignored" ]; then
		[ -z "${origins-}" ] && return 0
		err 1 ".poudriere.ports.ignored file is missing while EXPECTED_IGNORED is: ${origins}"
	fi

	tmp="$(mktemp -t queued)"
	cp -f "${log}/.poudriere.ports.ignored" "${tmp}"
	# First fix the list to expand main port FLAVORS
	expand_origin_flavors "${origins}" origins_expanded
	# The queue does remove duplicates - do the same here
	origins_expanded="$(echo "${origins_expanded}" | tr ' ' '\n' | sort -u | paste -s -d ' ' -)"
	echo "Asserting that only '${origins_expanded}' are in the ignored list" >&2
	for ignorespec in ${origins_expanded}; do
		case "${ignorespec}" in
		*:*)
			originspec="${ignorespec%:*}"
			ignorereason="${ignorespec#*:}"
			;;
		*)
			originspec="${ignorespec}"
			ignorereason=
		esac
		#fix_default_flavor "${originspec}" originspec
		hash_get originspec-pkgname "${originspec}" pkgname
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec} (is this pkg actually expected here?)"
		echo "=> Asserting that ${originspec} | ${pkgname} is ignored${ignorereason:+ with reason='${ignorereason}'}" >&2
		{ awk -vpkgname="${pkgname}" -voriginspec="${originspec}" \
		    -vignorereason="${ignorereason}" '
		    {reason=""; for (i=3;i<=NF;i++) { reason = (reason ? reason FS : "") $i } }
		    $1 == originspec && $2 == pkgname &&
		    (!ignorereason || reason == ignorereason) {
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
		' ${log}/.poudriere.ports.ignored; } >&2
		assert 0 $? "${originspec} | ${pkgname}${ignorereason:+ with reason='${ignorereason}'} should be ignored in ${log}/.poudriere.ports.ignored"
		# Remove the entry so we can assert later that nothing extra
		# is in the queue.
		{ awk -vpkgname="${pkgname}" -voriginspec="${originspec}" \
		        -vignorereason="${ignorereason}" '
		    {reason=""; for (i=3;i<=NF;i++) { reason = (reason ? reason FS : "") $i } }
		    $1 == originspec && $2 == pkgname &&
		    (!ignorereason || reason == ignorereason) { next }
		    { print }
		' "${tmp}"; } > "${tmp}.new"
		mv -f "${tmp}.new" "${tmp}"
	done
	echo "=> Asserting that nothing else is ignored" >&2
	if [ -s "${tmp}" ]; then
		echo "=> Items remaining:" >&2
		{ sed -e 's,^,==> ,' "${tmp}"; } >&2
	fi
	! [ -s "${tmp}" ]
	assert 0 $? "Ignore list should be empty"
	rm -f "${tmp}"
}

assert_inspected() {
	local origins="$1"
	local tmp originspec origins_expanded inspectspec inspectreason

	if [ ! -f "${log:?}/.poudriere.ports.inspected" ]; then
		[ -z "${origins-}" ] && return 0
		err 1 ".poudriere.ports.inspected file is missing while EXPECTED_IGNORED is: ${origins}"
	fi

	tmp="$(mktemp -t queued)"
	cp -f "${log}/.poudriere.ports.inspected" "${tmp}"
	# First fix the list to expand main port FLAVORS
	expand_origin_flavors "${origins}" origins_expanded
	# The queue does remove duplicates - do the same here
	origins_expanded="$(echo "${origins_expanded}" | tr ' ' '\n' | sort -u | paste -s -d ' ' -)"
	echo "Asserting that only '${origins_expanded}' are in the inspected list" >&2
	for inspectspec in ${origins_expanded}; do
		case "${inspectspec}" in
		*:*)
			originspec="${inspectspec%:*}"
			inspectreason="${inspectspec#*:}"
			;;
		*)
			originspec="${inspectspec}"
			inspectreason=
		esac
		#fix_default_flavor "${originspec}" originspec
		hash_get originspec-pkgname "${originspec}" pkgname
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec} (is this pkg actually expected here?)"
		echo "=> Asserting that ${originspec} | ${pkgname} is inspected${inspectreason:+ with reason='${inspectreason}'}" >&2
		{ awk -vpkgname="${pkgname}" -voriginspec="${originspec}" \
		    -vinspectreason="${inspectreason}" '
		    {reason=""; for (i=3;i<=NF;i++) { reason = (reason ? reason FS : "") $i } }
		    $1 == originspec && $2 == pkgname &&
		    (!inspectreason || reason == inspectreason) {
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
		' ${log}/.poudriere.ports.inspected; } >&2
		assert 0 $? "${originspec} | ${pkgname}${inspectreason:+ with reason='${inspectreason}'} should be inspected in ${log}/.poudriere.ports.inspected"
		# Remove the entry so we can assert later that nothing extra
		# is in the queue.
		{ awk -vpkgname="${pkgname}" -voriginspec="${originspec}" \
		        -vinspectreason="${inspectreason}" '
		    {reason=""; for (i=3;i<=NF;i++) { reason = (reason ? reason FS : "") $i } }
		    $1 == originspec && $2 == pkgname &&
		    (!inspectreason || reason == inspectreason) { next }
		    { print }
		' "${tmp}"; } > "${tmp}.new"
		mv -f "${tmp}.new" "${tmp}"
	done
	echo "=> Asserting that nothing else is inspected" >&2
	if [ -s "${tmp}" ]; then
		echo "=> Items remaining:" >&2
		{ sed -e 's,^,==> ,' "${tmp}"; } >&2
	fi
	! [ -s "${tmp}" ]
	assert 0 $? "Inspect list should be empty"
	rm -f "${tmp}"
}

assert_skipped() {
	local origins="$1"
	local tmp originspec origins_expanded skipspec skipreason

	if [ ! -f "${log:?}/.poudriere.ports.skipped" ]; then
		[ -z "${origins-}" ] && return 0
		err 1 ".poudriere.ports.skipped file is missing while EXPECTED_SKIPPED is: ${origins}"
	fi

	tmp="$(mktemp -t queued)"
	cp -f "${log}/.poudriere.ports.skipped" "${tmp}"
	# First fix the list to expand main port FLAVORS
	expand_origin_flavors "${origins}" origins_expanded
	# The queue does remove duplicates - do the same here
	origins_expanded="$(echo "${origins_expanded}" | tr ' ' '\n' | sort -u | paste -s -d ' ' -)"
	echo "Asserting that only '${origins_expanded}' are in the skipped list" >&2
	for skipspec in ${origins_expanded}; do
		case "${skipspec}" in
		*:*)
			originspec="${skipspec%:*}"
			skipreason="${skipspec#*:}"
			;;
		*)
			originspec="${skipspec}"
			skipreason=
		esac
		#fix_default_flavor "${originspec}" originspec
		hash_get originspec-pkgname "${originspec}" pkgname
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec} (is this pkg actually expected here?)"
		echo "=> Asserting that ${originspec} | ${pkgname} is skipped${skipreason:+ with reason ${skipreason}}" >&2
		{ awk -vpkgname="${pkgname}" -voriginspec="${originspec}" \
		    -vskipreason="${skipreason}" '
		    $1 == originspec && $2 == pkgname &&
		    (!skipreason || $3 == skipreason) {
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
		' ${log}/.poudriere.ports.skipped; } >&2
		assert 0 $? "${originspec} | ${pkgname} should be skipped in ${log}/.poudriere.ports.skipped${skipreason:+ with reason=${skipreason}}"
		# Remove the entry so we can assert later that nothing extra
		# is in the queue.
		{ awk -vpkgname="${pkgname}" -voriginspec="${originspec}" '
		    $1 == originspec && $2 == pkgname { next }
		    { print }
		' "${tmp}"; } > "${tmp}.new"
		mv -f "${tmp}.new" "${tmp}"
	done
	echo "=> Asserting that nothing else is skipped" >&2
	if [ -s "${tmp}" ]; then
		echo "=> Items remaining:" >&2
		{ sed -e 's,^,==> ,' "${tmp}"; } >&2
	fi
	! [ -s "${tmp}" ]
	assert 0 $? "Skipped list should be empty"
	rm -f "${tmp}"
}

assert_tobuild() {
	local origins="$1"
	local tmp originspec origins_expanded
	local buildspec rdep

	if [ ! -f "${log:?}/.poudriere.ports.tobuild" ]; then
		[ -z "${origins-}" ] && return 0
		err 1 ".poudriere.ports.tobuild file is missing while EXPECTED_TOBUILD is: ${origins}"
	fi

	tmp="$(mktemp -t queued)"
	cp -f "${log}/.poudriere.ports.tobuild" "${tmp}"
	# First fix the list to expand main port FLAVORS
	expand_origin_flavors "${origins}" origins_expanded
	# The queue does remove duplicates - do the same here
	origins_expanded="$(echo "${origins_expanded}" | tr ' ' '\n' | sort -u | paste -s -d ' ' -)"
	echo "Asserting that only '${origins_expanded}' are in the tobuild list" >&2
	for buildspec in ${origins_expanded}; do
		case "${buildspec}" in
		*:*)
			originspec="${buildspec%:*}"
			rdep="${buildspec#*:}"
			;;
		*)
			originspec="${buildspec}"
			rdep=
		esac
		#fix_default_flavor "${originspec}" originspec
		hash_get originspec-pkgname "${originspec}" pkgname
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec} (is this pkg actually expected here?)"
		echo "=> Asserting that ${originspec} | ${pkgname} is tobuild${rdep:+ with rdep ${rdep}}" >&2
		{ awk -vpkgname="${pkgname}" -voriginspec="${originspec}" \
		    -vrdep="${rdep}" '
		    $1 == originspec && $2 == pkgname && (!rdep || $3 == rdep) {
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
		' ${log}/.poudriere.ports.tobuild; } >&2
		assert 0 $? "${originspec} | ${pkgname} should be tobuild in ${log}/.poudriere.ports.tobuild${rdep:+ with rdep ${rdep}}"
		# Remove the entry so we can assert later that nothing extra
		# is in the queue.
		{ awk -vpkgname="${pkgname}" -voriginspec="${originspec}" '
		    $1 == originspec && $2 == pkgname { next }
		    { print }
		' "${tmp}"; } > "${tmp}.new"
		mv -f "${tmp}.new" "${tmp}"
	done
	echo "=> Asserting that nothing else is tobuild" >&2
	if [ -s "${tmp}" ]; then
		echo "=> Items remaining:" >&2
		{ sed -e 's,^,==> ,' "${tmp}"; } >&2
	fi
	! [ -s "${tmp}" ]
	assert 0 $? "Tobuild list should be empty"
	rm -f "${tmp}"
}

assert_built() {
	local origins="$1"
	local tmp originspec origins_expanded

	if [ ! -f "${log:?}/.poudriere.ports.built" ]; then
		[ -z "${origins-}" ] && return 0
		err 1 ".poudriere.ports.built file is missing while EXPECTED_BUILT is: ${origins}"
	fi

	tmp="$(mktemp -t queued)"
	cp -f "${log}/.poudriere.ports.built" "${tmp}"
	# First fix the list to expand main port FLAVORS
	expand_origin_flavors "${origins}" origins_expanded
	# The queue does remove duplicates - do the same here
	origins_expanded="$(echo "${origins_expanded}" | tr ' ' '\n' | sort -u | paste -s -d ' ' -)"
	echo "Asserting that only '${origins_expanded}' are in the built list" >&2
	for originspec in ${origins_expanded}; do
		# Trim away possible :reason leaked from EXPECTED_TOBUILD copy
		originspec="${originspec%:*}"
		#fix_default_flavor "${originspec}" originspec
		hash_get originspec-pkgname "${originspec}" pkgname
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec} (is this pkg actually expected here?)"
		echo "=> Asserting that ${originspec} | ${pkgname} is built" >&2
		{ awk -vpkgname="${pkgname}" -voriginspec="${originspec}" '
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
		' ${log}/.poudriere.ports.built; } >&2
		assert 0 $? "${originspec} | ${pkgname} should be built in ${log}/.poudriere.ports.built"
		# Remove the entry so we can assert later that nothing extra
		# is in the queue.
		{ awk -vpkgname="${pkgname}" -voriginspec="${originspec}" '
		    $1 == originspec && $2 == pkgname { next }
		    { print }
		' "${tmp}"; } > "${tmp}.new"
		mv -f "${tmp}.new" "${tmp}"
	done
	echo "=> Asserting that nothing else is built" >&2
	if [ -s "${tmp}" ]; then
		echo "=> Items remaining:" >&2
		{ sed -e 's,^,==> ,' "${tmp}"; } >&2
	fi
	! [ -s "${tmp}" ]
	assert 0 $? "Built list should be empty"
	rm -f "${tmp}"
}

assert_failed() {
	local origins="$1"
	local tmp originspec origins_expanded failedspec phase

	if [ ! -f "${log:?}/.poudriere.ports.failed" ]; then
		[ -z "${origins-}" ] && return 0
		err 1 ".poudriere.ports.failed file is missing while EXPECTED_FAILED is: ${origins}"
	fi

	tmp="$(mktemp -t queued)"
	cp -f "${log}/.poudriere.ports.failed" "${tmp}"
	# First fix the list to expand main port FLAVORS
	expand_origin_flavors "${origins}" origins_expanded
	# The queue does remove duplicates - do the same here
	origins_expanded="$(echo "${origins_expanded}" | tr ' ' '\n' | sort -u | paste -s -d ' ' -)"
	echo "Asserting that only '${origins_expanded}' are in the failed list" >&2
	for failedspec in ${origins_expanded}; do
		case "${failedspec}" in
		*:*)
			originspec="${failedspec%:*}"
			phase="${failedspec#*:}"
			;;
		*)
			originspec="${failedspec}"
			phase=
		esac
		#fix_default_flavor "${originspec}" originspec
		hash_get originspec-pkgname "${originspec}" pkgname
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec} (is this pkg actually expected here?)"
		echo "=> Asserting that ${originspec} | ${pkgname} is failed${phase:+ in phase ${phase}}" >&2
		{ awk -vpkgname="${pkgname}" -voriginspec="${originspec}" \
		     -vfailedreason="${phase}" '
		    $1 == originspec && $2 == pkgname &&
		    (!phase || $3 == phase) {
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
		' ${log}/.poudriere.ports.failed; } >&2
		assert 0 $? "${originspec} | ${pkgname} should be failed in ${log}/.poudriere.ports.failed${phase:+ in phase ${phase}}"
		# Remove the entry so we can assert later that nothing extra
		# is in the queue.
		{ awk -vpkgname="${pkgname}" -voriginspec="${originspec}" '
		    $1 == originspec && $2 == pkgname { next }
		    { print }
		' "${tmp}"; } > "${tmp}.new"
		mv -f "${tmp}.new" "${tmp}"
	done
	echo "=> Asserting that nothing else is failed" >&2
	if [ -s "${tmp}" ]; then
		echo "=> Items remaining:" >&2
		{ sed -e 's,^,==> ,' "${tmp}"; } >&2
	fi
	! [ -s "${tmp}" ]
	assert 0 $? "Failed list should be empty"
	rm -f "${tmp}"
}

assert_counts() {
	local queued expected_queued ignored expected_ignored
	local inspected expected_inspected
	local skipped expected_skipped
	local tobuild expected_tobuild computed_remaining
	local failed expected_failed
	local fetched expected_fetched
	local built expected_built

	expected_tobuild=$(expand_and_count "${EXPECTED_TOBUILD-}")
	expected_ignored=$(expand_and_count "${EXPECTED_IGNORED-}")
	expected_inspected=$(expand_and_count "${EXPECTED_INSPECTED-}")
	expected_skipped=$(expand_and_count "${EXPECTED_SKIPPED-}")
	expected_failed=$(expand_and_count "${EXPECTED_FAILED-}")
	expected_fetched=$(expand_and_count "${EXPECTED_FETCHED-}")
	expected_built=$(expand_and_count "${EXPECTED_BUILT-}")
	expected_queued=$(expand_and_count "${EXPECTED_QUEUED-}")
	echo "=> Asserting queued=${expected_queued} built=${expected_built} failed=${expected_failed} ignored=${expected_ignored} inspected=${expected_inspected} skipped=${expected_skipped} fetched=${expected_fetched} tobuild=${expected_tobuild}"

	if [ -e "${log:?}/.poudriere.stats_queued" ]; then
		read queued < "${log:?}/.poudriere.stats_queued"
		assert 0 $? "${log:?}/.poudriere.stats_queued read should pass"
	else
		queued=0
	fi
	assert "${expected_queued}" "${queued}" "queued should match"

	if [ -n "${EXPECTED_IGNORED-}" ]; then
		read ignored < "${log:?}/.poudriere.stats_ignored"
		assert 0 $? "${log:?}/.poudriere.stats_ignored read should pass"
	else
		ignored=0
	fi
	assert "${expected_ignored}" "${ignored}" "ignored should match"

	if [ -n "${EXPECTED_INSPECTED-}" ]; then
		read inspected < "${log:?}/.poudriere.stats_inspected"
		assert 0 $? "${log:?}/.poudriere.stats_inspected read should pass"
	else
		inspected=0
	fi
	assert "${expected_inspected}" "${inspected}" "inspected should match"


	if [ -n "${EXPECTED_SKIPPED-}" ]; then
		read skipped < "${log:?}/.poudriere.stats_skipped"
		assert 0 $? "${log:?}/.poudriere.stats_skipped read should pass"
	else
		skipped=0
	fi
	assert "${expected_skipped}" "${skipped}" "skipped should match"

	if [ -n "${EXPECTED_TOBUILD-}" ]; then
		read tobuild < "${log}/.poudriere.stats_tobuild"
		assert 0 $? "${log}/.poudriere.stats_tobuild read should pass"
	else
		tobuild=0
	fi
	assert "${expected_tobuild}" "${tobuild}" "tobuild should match"

	if [ -n "${EXPECTED_BUILT-}" ]; then
		read built < "${log}/.poudriere.stats_built"
		assert 0 $? "${log}/.poudriere.stats_built read should pass"
	else
		built=0
	fi
	assert "${expected_built}" "${built}" "built should match"

	if [ -n "${EXPECTED_FETCHED-}" ]; then
		read fetched < "${log}/.poudriere.stats_fetched"
		assert 0 $? "${log}/.poudriere.stats_fetched read should pass"
	else
		fetched=0
	fi
	assert "${expected_fetched}" "${fetched}" "fetched should match"

	if [ -n "${EXPECTED_FAILED-}" ]; then
		read failed < "${log}/.poudriere.stats_failed"
		assert 0 $? "${log}/.poudriere.stats_failed read should pass"
	else
		failed=0
	fi
	assert "${expected_failed}" "${failed}" "failed should match"

	# Ensure the computed stat is correct
	# If we did a real build, without crashing, then all of the stats
	# should add to 0.
	case "${EXPECTED_BUILT:+set}" in
	set)
		computed_remaining=$((expected_queued - \
		    (expected_ignored + expected_inspected + \
		     expected_skipped + expected_built + \
		     expected_fetched + expected_failed)))
		assert "0" "${computed_remaining}" \
		    "Computed remaining should be 0 on a non-crash build - this being wrong could indicate show_build_summary() is wrong too"
		;;
	*)
		# For a dry-run, remainining should match tobuild.
		computed_remaining=$((expected_queued - \
		    (expected_ignored + expected_inspected + expected_skipped)))
		assert "${expected_tobuild}" "${computed_remaining}" \
		    "Computed remaining should match remaining for a dry-run"
		;;
	esac
}

showfile() {
	local file="$1"

	{
		msg "File '${file}':"
		sed -e 's,^,'$'\t'',' "${file}"
	} >&${REDIRECTED_STDERR_FD:-2}
}

do_poudriere() {
	local verbose n file
	local -

	n=0
	until [ "${n}" -eq "${VERBOSE}" ]; do
		[ -z "${verbose}" ] && verbose=-
		verbose="${verbose}v"
		n=$((n + 1))
	done
	for file in \
	    "${POUDRIERE_ETC:?}/poudriere.d/"poudriere.conf \
	    ${JAILNAME:+"${POUDRIERE_ETC:?}/poudriere.d/${MASTERNAME:?}-poudriere.conf"} \
	    ${JAILNAME:+"${POUDRIERE_ETC:?}/poudriere.d/${JAILNAME}-poudriere.conf"} \
	    ${SETNAME:+"${POUDRIERE_ETC:?}/poudriere.d/${SETNAME}-poudriere.conf"} \
	    ${PTNAME:+"${POUDRIERE_ETC:?}/poudriere.d/${PTNAME}-poudriere.conf"} \
	    ; do
		if [ -r "${file}" ]; then
			showfile "${file}"
		fi
	done
	msg "Running: ${POUDRIEREPATH} -e ${POUDRIERE_ETC} -d -E ${verbose}" "$@"
	${SUDO} ${POUDRIEREPATH} -e ${POUDRIERE_ETC} -d -E ${verbose} "$@"
}

_setup_overlays() {
	local omnt oname

	# Setup basic overlay to test-ports/overlay/ dir.
	case "${OVERLAYSDIR-}" in
	"/overlays")
		OVERLAYSDIR="$(mktemp -ut overlays)"
		;;
	esac
	mkdir -p "${MASTERMNT:?}/${OVERLAYSDIR:?}"
	REAL_OVERLAYS=
	for o in ${OVERLAYS}; do
		# This is the git checkout dir test-ports/${o}
		omnt="${PTMNT%/*}/${o}"
		[ -d "${omnt}" ] || continue
		oname=$(echo "${omnt}" | tr '[./]' '_')
		# A previous run may have already setup this overlay.
		case "$(realpath -q "${MASTERMNT:?}/${OVERLAYSDIR:?}/${oname:?}" || :)" in
		"$(realpath "${omnt}")")
			REAL_OVERLAYS="${REAL_OVERLAYS:+${REAL_OVERLAYS} }${oname}"
			continue
			;;
		esac
		pset "${oname}" mnt "${omnt}"
		pset "${oname}" method "-"
		# We run port_var_fetch_originspec without a jail so can't use plain
		# /overlays. Need to link the host path into our fake MASTERMNT path
		# as well as link to the overlay portdir without nullfs.
		#mkdir -p "${MASTERMNT:?}/${OVERLAYSDIR%/*}"
		ln -hfs "${MASTERMNT:?}/${OVERLAYSDIR:?}" "${OVERLAYSDIR:?}"
		ln -hfs "${omnt:?}" "${MASTERMNT:?}/${OVERLAYSDIR:?}/${oname:?}"
		REAL_OVERLAYS="${REAL_OVERLAYS:+${REAL_OVERLAYS} }${oname}"
	done
	SAVE_OVERLAYS="${OVERLAYS}"
	recache_pkgnames
}

_setup_build() {
	local __MAKE_CONF __make_conf_orig OVERLAYS

	if [ ${ALL:-0} -eq 0 ]; then
		assert_not "" "${LISTPORTS}" "LISTPORTS empty"
	fi

	_setup_overlays
	OVERLAYS="${REAL_OVERLAYS-}"
	export OVERLAYS

	ALL_PKGNAMES=
	ALL_ORIGINS=
	if [ ${ALL} -eq 1 ]; then
		LISTPORTS="$(set_pipefail; set -e; listed_ports | paste -s -d ' ' -)"
		assert 0 "$?"
	fi
	LISTPORTS="$(sorted "${LISTPORTS}")"
	if [ "${FLAVOR_DEFAULT_ALL-null}" == "yes" ]; then
		LISTPORTS="$(echo "${LISTPORTS}" | tr ' ' '\n' |
		    sed -e 's,$,@all,' | paste -s -d ' ' -)"
	fi
	__make_conf_orig="${__MAKE_CONF}"
	__MAKE_CONF="$(mktemp -ut make.conf)"
	{ cat "${__make_conf_orig}" \
	    "${POUDRIERE_ETC:?}/poudriere.d/${MASTERNAME:?}-make.conf"; } \
	    > "${__MAKE_CONF}"
	export __MAKE_CONF
	showfile "${__MAKE_CONF}"
	echo -n "Gathering metadata for requested ports..."
	for origin in ${LISTPORTS}; do
		cache_pkgnames 0 "${origin}" || :
	done
	echo " done"
	expand_origin_flavors "${LISTPORTS}" LISTPORTS_EXPANDED
	fetch_global_port_vars || err 99 "Unable to fetch port vars"
	assert_not "null" "${P_PORTS_FEATURES-null}" "fetch_global_port_vars should work"
	echo "Building: $(echo ${LISTPORTS_EXPANDED})"
	newbuild
	rm -f "${__MAKE_CONF}"
}

list_package_files() {
	# find -ls seems nice here but it displays 'st_blocks' which can be
	# delay-modified on ZFS
	(
		cd "${PACKAGES:?}/All/" || return
		find -x . \( -type f -o -type l \) \
		    -exec ls -alioT {} +
	)
}

do_bulk() {
	_setup_build
	case "$@" in
	*-n*)
		case "$@" in
		*-c*) ;;
		*)
			DRY_RUN_PACKAGES_LIST="$(mktemp -ut packages_for_dry_run)"
			if [ -d "${PACKAGES:?}/All/" ]; then
				list_package_files
			fi > "${DRY_RUN_PACKAGES_LIST:?}"
		esac
		;;
	esac
	do_poudriere bulk \
	    ${REAL_OVERLAYS:+$(echo "${REAL_OVERLAYS}" | tr ' ' '\n' | sed -e 's,^,-O ,' | paste -d ' ' -s -)} \
	    ${JFLAG:+-J ${JFLAG}} \
	    -B "${BUILDNAME:?}" \
	    -j "${JAILNAME}" -p "${PTNAME}" ${SETNAME:+-z "${SETNAME}"} \
	    "$@"
}

do_testport() {
	_setup_build
	do_poudriere testport \
	    ${REAL_OVERLAYS:+$(echo "${REAL_OVERLAYS}" | tr ' ' '\n' | sed -e 's,^,-O ,' | paste -d ' ' -s -)} \
	    ${JFLAG:+-J ${JFLAG}} \
	    -B "${BUILDNAME:?}" \
	    -j "${JAILNAME}" -p "${PTNAME}" ${SETNAME:+-z "${SETNAME}"} \
	    "$@"
}

do_distclean() {
	_setup_overlays
	do_poudriere distclean \
	    ${REAL_OVERLAYS:+$(echo "${REAL_OVERLAYS}" | tr ' ' '\n' | sed -e 's,^,-O ,' | paste -d ' ' -s -)} \
	    ${JFLAG:+-J ${JFLAG}} \
	    -p "${PTNAME}" \
	    "$@"
}

do_options() {
	_setup_overlays
	do_poudriere options \
	    ${REAL_OVERLAYS:+$(echo "${REAL_OVERLAYS}" | tr ' ' '\n' | sed -e 's,^,-O ,' | paste -d ' ' -s -)} \
	    ${PORT_DBDIRNAME:+-o "${PORT_DBDIRNAME}"} \
	    -j "${JAILNAME}" -p "${PTNAME}" ${SETNAME:+-z "${SETNAME}"} \
	    "$@"
}

do_pkgclean() {
	_setup_overlays
	case "$@" in
	*-A*) ;;
	*)
		# pkg is needed for pkgclean if not removing all.
		do_bulk ports-mgmt/pkg
		assert 0 "$?" "bulk for pkg should pass"
		;;
	esac
	do_poudriere pkgclean \
	    ${REAL_OVERLAYS:+$(echo "${REAL_OVERLAYS}" | tr ' ' '\n' | sed -e 's,^,-O ,' | paste -d ' ' -s -)} \
	    ${JFLAG:+-J ${JFLAG}} \
	    -j "${JAILNAME}" -p "${PTNAME}" ${SETNAME:+-z "${SETNAME}"} \
	    "$@"
}

do_pkgclean_smoke() {
	allpackages="$(/bin/ls ${PACKAGES:?}/All/)"
	assert 0 "$?"
	assert_not "" "${allpackages}" "Packages were not built"

	do_pkgclean ${LISTPORTS:?}
	assert 0 $? "Pkgclean should pass"

	nowpackages="$(/bin/ls ${PACKAGES:?}/All/)"
	assert 0 "$?"
	assert "${allpackages}" "${nowpackages}" "No packages should have been removed"

	do_pkgclean -y -A
	assert 0 $? "Pkgclean should pass"

	nowpackages="$(/bin/ls ${PACKAGES:?}/All/)"
	assert 0 "$?"
	assert "" "${nowpackages}" "All packages should have been removed"
}

count() {
	local count
	if [ "$#" -eq 0 ]; then
		count=0
	else
		count=$(echo "$@" | tr ' ' '\n' | LC_ALL=C sort -u |
		    sed -e '/^$/d' | wc -l)
		count="${count##* }"
	fi
	echo "${count}"
}

expand_and_count() {
	[ "$#" -eq 1 ] || eargs expand_and_count expected_list
	local expected_list="$1"
	local expanded_list

	expand_origin_flavors "${expected_list?}" expanded_list
	count "${expanded_list?}"
}

_assert_bulk_queue_and_stats() {
	local expanded_LISTPORTS_NOIGNORED
	local port
	local -

	set -u
	### Now do tests against the output of the bulk run. ###

	# Assert the IGNOREd ports are tracked in .poudriere.ports.ignored
	echo >&2
	stack_lineinfo assert_ignored "${EXPECTED_IGNORED-}"

	# Assert the inspected ports are tracked in .poudriere.ports.inspected
	echo >&2
	stack_lineinfo assert_inspected "${EXPECTED_INSPECTED-}"

	# Assert that SKIPPED ports are right
	echo >&2
	stack_lineinfo assert_skipped "${EXPECTED_SKIPPED-}"

	# Assert that all expected dependencies are in poudriere.ports.queued
	# (since they do not exist yet)
	echo >&2
	stack_lineinfo assert_queued "" "${EXPECTED_QUEUED-}"

	echo >&2
	case "${EXPECTED_LISTED+set}" in
	set)
		stack_lineinfo assert_metadata "listed" "${EXPECTED_LISTED}"
		;;
	*)
		stack_lineinfo assert_metadata "listed" "${LISTPORTS}"
		;;
	esac

	case "${EXPECTED_TOBUILD-null}" in
	null) EXPECTED_TOBUILD="${EXPECTED_QUEUED-}" ;;
	esac
	case "${EXPECTED_TOBUILD+set}" in
	set)
		echo >&2
		stack_lineinfo assert_tobuild "${EXPECTED_TOBUILD?}"
		;;
	esac

	# Assert stats counts are right
	echo >&2
	stack_lineinfo assert_counts
}
alias assert_bulk_queue_and_stats='stack_lineinfo _assert_bulk_queue_and_stats '

_assert_bulk_dry_run() {
	local log logfile tmp

	_log_path log || err 99 "Unable to determine logdir"

	# No logfiles should be created in the build dir.
	# A directory is OK
	assert_true [ -d "${log:?}/logs/" ]
	assert_true [ -d "${log:?}/logs/errors" ]
	assert_true [ -d "${log:?}/logs/fetched" ]
	assert_true [ -d "${log:?}/logs/built" ]
	assert_true [ -d "${log:?}/logs/ignored" ]
	assert "built errors fetched ignored" \
	    "$(/bin/ls "${log:?}/logs/" | paste -d ' ' -s -)" \
	    "Logdir '${log:?}/logs' should have no logs"
	assert "" "$(/bin/ls "${log:?}/logs/errors")" \
	    "Logdir '${log:?}/logs/errors' should be empty"
	assert "" "$(/bin/ls "${log:?}/logs/fetched")" \
	    "Logdir '${log:?}/logs/fetched' should be empty"
	assert "" "$(/bin/ls "${log:?}/logs/built")" \
	    "Logdir '${log:?}/logs/built' should be empty"
	assert "" "$(/bin/ls "${log:?}/logs/ignored")" \
	    "Logdir '${log:?}/logs/ignored' should be empty"

	# Packages should be untouched.
	case "${DRY_RUN_PACKAGES_LIST:+set}" in
	set)
		tmp="$(mktemp -u)"
		if [ -d "${PACKAGES:?}/All/" ]; then
			list_package_files
		fi > "${tmp:?}"
		stack_lineinfo assert_file "${tmp}" "${DRY_RUN_PACKAGES_LIST:?}"
		;;
	esac
	# No .building dir should be left behind
	assert_false [ -d "${PACKAGES:?}/.building" ]
}
alias assert_bulk_dry_run='stack_lineinfo _assert_bulk_dry_run '

_assert_bulk_build_results() {
	local pkgname file file2 log originspec origin flavor flavor2 subpkg
	local PKG_BIN pkg_originspec pkg_origin pkg_flavor
	local built_origins_expanded built_pkgnames TESTPKGNAME TESTPORT
	local failed_origins_expanded failed_pkgnames failedspec
	local skipped_origins_expanded skipped_pkgnames skippedspec
	local ignore_origins_expanded ignore_pkgnames ignorespec
	local inspect_origins_expanded inspect_pkgnames inspectspec

	which -s "${PKG_BIN:?}" || err 99 "Unable to find in host: ${PKG_BIN}"
	_log_path log || err 99 "Unable to determine logdir"
	case "${DRY_RUN_PACKAGES_LIST:+set}" in
	set) unlink "${DRY_RUN_PACKAGES_LIST}" ;;
	esac

	assert_ret 0 [ -d "${PACKAGES}" ]
	assert 0 $? "PACKAGES directory should exist: ${PACKAGES}"

	expand_origin_flavors "${EXPECTED_BUILT?}" built_origins_expanded
	built_pkgnames=
	TESTPKGNAME=
	for originspec in ${built_origins_expanded}; do
		# Trim away possible :reason leaked from EXPECTED_TOBUILD copy
		originspec="${originspec%:*}"
		hash_get originspec-pkgname "${originspec}" pkgname
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec} (is this pkg actually expected here?)"
		built_pkgnames="${built_pkgnames:+${built_pkgnames} }${pkgname}"
		case "${TESTPORT:+set}" in
		set)
			fix_default_flavor "${originspec}" originspec
			fix_default_flavor "${TESTPORT}" TESTPORT
			case "${originspec}" in
			"${TESTPORT}")
				TESTPKGNAME="${pkgname}"
				;;
			esac
			;;
		esac
	done

	expand_origin_flavors "${EXPECTED_FAILED-}" failed_origins_expanded
	failed_pkgnames=
	for failedspec in ${failed_origins_expanded}; do
		case "${failedspec}" in
		*:*)
			originspec="${failedspec%:*}"
			;;
		*)
			originspec="${failedspec}"
		esac
		hash_get originspec-pkgname "${originspec}" pkgname
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec} (is this pkg actually expected here?)"
		failed_pkgnames="${failed_pkgnames:+${failed_pkgnames} }${pkgname}"
		case "${TESTPORT:+set}" in
		set)
			fix_default_flavor "${originspec}" originspec
			fix_default_flavor "${TESTPORT}" TESTPORT
			case "${originspec}" in
			"${TESTPORT}")
				TESTPKGNAME="${pkgname}"
				;;
			esac
			;;
		esac
	done

	expand_origin_flavors "${EXPECTED_IGNORED-}" ignored_origins_expanded
	ignored_pkgnames=
	for ignoredspec in ${ignored_origins_expanded}; do
		case "${ignoredspec}" in
		*:*)
			originspec="${ignoredspec%:*}"
			;;
		*)
			originspec="${ignoredspec}"
		esac
		hash_get originspec-pkgname "${originspec}" pkgname
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec} (is this pkg actually expected here?)"
		ignored_pkgnames="${ignored_pkgnames:+${ignored_pkgnames} }${pkgname}"
		case "${TESTPORT:+set}" in
		set)
			fix_default_flavor "${originspec}" originspec
			fix_default_flavor "${TESTPORT}" TESTPORT
			case "${originspec}" in
			"${TESTPORT}")
				TESTPKGNAME="${pkgname}"
				;;
			esac
			;;
		esac
	done

	expand_origin_flavors "${EXPECTED_INSPECTED-}" inspected_origins_expanded
	inspected_pkgnames=
	for inspectedspec in ${inspected_origins_expanded}; do
		case "${inspectedspec}" in
		*:*)
			originspec="${inspectedspec%:*}"
			;;
		*)
			originspec="${inspectedspec}"
		esac
		hash_get originspec-pkgname "${originspec}" pkgname
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec} (is this pkg actually expected here?)"
		inspected_pkgnames="${inspected_pkgnames:+${inspected_pkgnames} }${pkgname}"
		case "${TESTPORT:+set}" in
		set)
			fix_default_flavor "${originspec}" originspec
			fix_default_flavor "${TESTPORT}" TESTPORT
			case "${originspec}" in
			"${TESTPORT}")
				TESTPKGNAME="${pkgname}"
				;;
			esac
			;;
		esac
	done

	expand_origin_flavors "${EXPECTED_SKIPPED-}" skipped_origins_expanded
	skipped_pkgnames=
	for skippedspec in ${skipped_origins_expanded}; do
		case "${skippedspec}" in
		*:*)
			originspec="${skippedspec%:*}"
			;;
		*)
			originspec="${skippedspec}"
		esac
		hash_get originspec-pkgname "${originspec}" pkgname
		assert_not '' "${pkgname}" "PKGNAME needed for ${originspec} (is this pkg actually expected here?)"
		skipped_pkgnames="${skipped_pkgnames:+${skipped_pkgnames} }${pkgname}"
		case "${TESTPORT:+set}" in
		set)
			fix_default_flavor "${originspec}" originspec
			fix_default_flavor "${TESTPORT}" TESTPORT
			case "${originspec}" in
			"${TESTPORT}")
				TESTPKGNAME="${pkgname}"
				;;
			esac
			;;
		esac
	done

	echo "Asserting that packages were built"
	for pkgname in ${built_pkgnames}; do
		file="${PACKAGES}/All/${pkgname}${P_PKG_SUFX}"
		case "${pkgname}" in
		"${TESTPKGNAME}")
			# testport does not produce a package for the target
			# port
			assert_ret_not 0 [ -f "${file}" ]
			assert 0 $? "Package should NOT exist: ${file}"
			continue
			;;
		esac
		assert_ret 0 [ -f "${file}" ]
		assert_ret 0 [ -s "${file}" ]
		assert 0 $? "Package should not be empty: ${file}"
	done
	for pkgname in ${failed_pkgnames} ${skipped_pkgnames}; do
		file="${PACKAGES}/All/${pkgname}${P_PKG_SUFX}"
		case "${pkgname}" in
		"${TESTPKGNAME}")
			# testport does not produce a package for the target
			# port
			assert_ret_not 0 [ -f "${file}" ]
			assert 0 $? "Package should NOT exist: ${file}"
			continue
			;;
		esac
		# crashed tests may produce a package even with failure
		case " ${EXPECTED_CRASHED-} " in
		*" ${pkgname} "*) ;;
		*)
			assert_ret_not 0 [ -f "${file}" ]
			;;
		esac
	done

	echo "Asserting that logfiles were produced"
	for pkgname in ${built_pkgnames}; do
		file="${log:?}/logs/${pkgname}.log"
		assert_ret 0 [ -f "${file}" ]
		assert 0 $? "Logfile should exist: ${file}"
		assert_ret 0 [ -s "${file}" ]
		assert 0 $? "Logfile should not be empty: ${file}"
		# crashed build may still get a built package
		case " ${EXPECTED_CRASHED-} " in
		*" ${pkgname} "*)
			assert_ret 0 grep "build crashed:" "${file}"
			;;
		*)
			assert_ret_not 0 grep "build crashed:" "${file}"
			assert_ret_not 0 grep "build failure encountered" \
			    "${file}"
			;;
		esac
		hash_get pkgname-originspec "${pkgname}" originspec ||
			err 99 "Unable to find originspec for pkgname: ${pkgname}"
		grep '^build of.*ended at' "${file}" || :
		assert_ret 0 grep "build of ${originspec} | ${pkgname} ended at" \
		    "${file}"

		file2="${log:?}/logs/built/${pkgname}.log"
		assert_ret 0 [ -r "${file2}" ]
		assert_ret 0 [ -L "${file2}" ]
		assert "$(realpath "${file}")" "$(realpath "${file}")"
	done
	for pkgname in ${failed_pkgnames}; do
		file="${log:?}/logs/${pkgname}.log"
		assert_ret 0 [ -f "${file}" ]
		assert 0 $? "Logfile should exist: ${file}"
		assert_ret 0 [ -s "${file}" ]
		assert 0 $? "Logfile should not be empty: ${file}"
		assert_ret 0 grep "build failure encountered" "${file}"
		hash_get pkgname-originspec "${pkgname}" originspec ||
			err 99 "Unable to find originspec for pkgname: ${pkgname}"
		grep '^build of.*ended at' "${file}" || :
		assert_ret 0 grep "build of ${originspec} | ${pkgname} ended at" \
		    "${file}"

		file2="${log:?}/logs/errors/${pkgname}.log"
		assert_ret 0 [ -r "${file2}" ]
		assert_ret 0 [ -L "${file2}" ]
		assert "$(realpath "${file}")" "$(realpath "${file}")"
	done
	case "${LOGS_FOR_IGNORED-}" in
	"yes")
		for pkgname in ${ignored_pkgnames}; do
			file="${log:?}/logs/${pkgname}.log"
			assert_ret 0 [ -f "${file}" ]
			assert 0 $? "Logfile should exist: ${file}"
			assert_ret 0 [ -s "${file}" ]
			assert 0 $? "Logfile should not be empty: ${file}"
			assert_ret 0 grep "Ignoring:" "${file}"
			hash_get pkgname-originspec "${pkgname}" originspec ||
				err 99 "Unable to find originspec for pkgname: ${pkgname}"
			grep '^build of.*ended at' "${file}" || :
			assert_ret 0 grep "build of ${originspec} | ${pkgname} ended at" \
			    "${file}"

			file2="${log:?}/logs/ignored/${pkgname}.log"
			assert_ret 0 [ -r "${file2}" ]
			assert_ret 0 [ -L "${file2}" ]
			assert "$(realpath "${file}")" "$(realpath "${file}")"
		done
		;;
	esac
	for pkgname in ${skipped_pkgnames}; do
		file="${log:?}/logs/${pkgname}.log"
		assert_ret_not 0 [ -f "${file}" ]
		assert 0 $? "Logfile should not exist: ${file}"
	done

	echo "Asserting package metadata sanity check"
	for pkgname in ${built_pkgnames}; do
		case "${pkgname}" in
		"${TESTPKGNAME}")
			# testport does not produce a package for the target
			# port
			continue
			;;
		esac
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

	stack_lineinfo assert_built "${EXPECTED_BUILT?}"
	stack_lineinfo assert_failed "${EXPECTED_FAILED-}"
}
alias assert_bulk_build_results='stack_lineinfo _assert_bulk_build_results '

newbuild() {
	BUILDNAME="$(date +%s)"
	_log_path log
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

SCRIPTNAME="${SCRIPTNAME##*/}"
POUDRIERE="env VERBOSE=0 ${POUDRIEREPATH} -e ${POUDRIERE_ETC}"
ARCH=$(uname -p)
# Need to keep JAILNAME unique but not full of spam as it gets into every path
# and makes debugging multiple worktrees difficult. Just hash the srcdir
# into the name.
JAILNAME="poudriere-test-${ARCH}-$(realpath "${am_abs_top_srcdir:?}" | sha256 | cut -c1-6)"
JAIL_VERSION="13.5-RELEASE"
JAILMNT=$(${POUDRIERE} api "jget ${JAILNAME} mnt || echo" || echo)
export UNAME_r=$(freebsd-version)
export UNAME_v="FreeBSD ${UNAME_r}"
if [ -n "${JAILMNT}" ] && [ -z "${TEST_CONTEXTS_NUM_CHECK-}" ]; then
	# Ensure it is up-to-date otherwise delete it so it can be updated.
	JAIL_VERSION_CUR=$(${POUDRIERE} api "jget ${JAILNAME} version || echo" || echo)
	case "${JAIL_VERSION_CUR}" in
	"${JAIL_VERSION}") ;;
	*)
		# Needs to be updated.
		echo "Test jail needs to be updated..." >&2
		if [ ${BOOTSTRAP_ONLY:-0} -eq 0 ]; then
			echo "ERROR: Must run prep.sh" >&2
			exit 99
		fi
		if ! ${SUDO} ${POUDRIERE} jail -d -j "${JAILNAME}"; then
			echo "SKIP: Cannot upgrade jail with Poudriere" >&2
			exit 77
		fi
		JAILMNT=
		;;
	esac
fi
if [ -z "${JAILMNT}" ] && [ -z "${TEST_CONTEXTS_NUM_CHECK-}" ]; then
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
	JAILMNT=$(${POUDRIERE} api "jget ${JAILNAME} mnt || echo" || echo)
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

: "${TEST_PORTSDIR:=default}"
: "${PORTSDIR:="${am_abs_top_srcdir:?}/test-ports/${TEST_PORTSDIR:?}"}"
export PORTSDIR
PTMNT="${PORTSDIR}"
#: ${PTNAME:=${PTMNT##*/}}
: ${PTNAME:=$(echo "${TEST_PORTSDIR}" | tr '[./]' '_')}
: ${SETNAME:="${SCRIPTNAME%.sh}${TEST_NUMS:+$(echo "${TEST_NUMS}" | tr ' ' '_')}"}
export PORT_DBDIR=/dev/null
export __MAKE_CONF="${POUDRIERE_ETC}/poudriere.d/make.conf"
export SRCCONF=/dev/null
export SRC_ENV_CONF=/dev/null
export PACKAGE_BUILDING=yes
MASTERNAME="${JAILNAME:?}-${PTNAME:?}-${SETNAME:?}"
_mastermnt MASTERMNT

set_blacklist() {
	local blacklist

	blacklist="${POUDRIERE_ETC:?}/poudriere.d/${MASTERNAME:?}-blacklist"
	msg "Updating ${blacklist}" >&2
	write_atomic_cmp "${blacklist}"
	showfile "${blacklist}"
}
if [ -z "${TEST_CONTEXTS_NUM_CHECK-}" ]; then
set_blacklist <<-EOF
EOF
fi

set_poudriere_conf() {
	local poudriere_conf

	# Compat - Remove older setname-poudriere.conf which multiple checkouts
	# could race on.
	poudriere_conf="${POUDRIERE_ETC:?}/poudriere.d/${SETNAME:?}-poudriere.conf"
	rm -f "${poudriere_conf}"

	poudriere_conf="${POUDRIERE_ETC:?}/poudriere.d/${MASTERNAME:?}-poudriere.conf"
	msg "Updating ${poudriere_conf}" >&2
	write_atomic_cmp "${poudriere_conf}" <<-EOF
	${POUDRIERE_TMPDIR:+TMPDIR="${POUDRIERE_TMPDIR}"}
	KEEP_OLD_PACKAGES=yes
	KEEP_OLD_PACKAGES_COUNT=${KEEP_OLD_PACKAGES_COUNT:=10}
	NOHANG_TIME=${NOHANG_TIME:-60}
	MAX_EXECUTION_TIME=${MAX_EXECUTION_TIME:-900}
	${FLAVOR_DEFAULT_ALL:+FLAVOR_DEFAULT_ALL=${FLAVOR_DEFAULT_ALL}}
	${FLAVOR_ALL:+FLAVOR_ALL=${FLAVOR_ALL}}
	${IMMUTABLE_BASE:+IMMUTABLE_BASE=${IMMUTABLE_BASE}}
	${BUILD_AS_NON_ROOT:+BUILD_AS_NON_ROOT=${BUILD_AS_NON_ROOT}}
	${LOGS_FOR_IGNORED:+LOGS_FOR_IGNORED=${LOGS_FOR_IGNORED}}
	$(cat)
	EOF
	showfile "${poudriere_conf}"
}
if [ -z "${TEST_CONTEXTS_NUM_CHECK-}" ]; then
set_poudriere_conf <<-EOF
EOF
fi

set_make_conf() {
	local make_conf

	# Compat - Remove older setname-make.conf which multiple checkouts
	# could race on.
	make_conf="${POUDRIERE_ETC:?}/poudriere.d/${SETNAME:?}-make.conf"
	rm -f "${make_conf}"

	make_conf="${POUDRIERE_ETC:?}/poudriere.d/${MASTERNAME:?}-make.conf"
	msg "Updating ${make_conf}" >&2
	write_atomic_cmp "${make_conf}"
	showfile "${make_conf}"
	recache_pkgnames
}
if [ -z "${TEST_CONTEXTS_NUM_CHECK-}" ]; then
# Start empty
set_make_conf <<-EOF
EOF
fi

do_logclean() {
	local ret

	echo -n "Pruning stale jails..."
	ret=0
	${SUDO} ${POUDRIEREPATH} -e ${POUDRIERE_ETC} jail -k \
	    -j "${JAILNAME}" -p "${PTNAME}" ${SETNAME:+-z "${SETNAME}"} ||
	    ret="$?"
	echo " done"
	case "${ret}" in
	0) ;;
	*) err 99 "jail cleanup failed ret=${ret}" ;;
	esac
	echo -n "Pruning previous logs..."
	ret=0
	${SUDO} ${POUDRIEREPATH} -e ${POUDRIERE_ETC} logclean \
	    -j "${JAILNAME}" -p "${PTNAME}" ${SETNAME:+-z "${SETNAME}"} \
	    -y -N ${KEEP_LOGS_COUNT-10} -w ${LOGCLEAN_WAIT-30} || ret="$?"
	case "${ret}" in
	0|124) ;;
	*) err 99 "logclean failure ret=${ret}" ;;
	esac
	echo " done"
}
if [ -z "${TEST_CONTEXTS_NUM_CHECK-}" ]; then
	do_logclean >&${REDIRECTED_STDERR_FD:-2}
fi

# Import local ports tree
pset "${PTNAME}" mnt "${PTMNT}"
pset "${PTNAME}" method "-"

export POUDRIERE_BUILD_TYPE=bulk
: ${PACKAGES:=${POUDRIERE_DATA:?}/packages/${MASTERNAME:?}}
: ${LOCALBASE:=/usr/local}
: ${PKG_BIN:=${LOCALBASE}/sbin/pkg-static}
set +e
