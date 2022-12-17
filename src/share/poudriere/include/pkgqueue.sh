#!/bin/sh
# 
# Copyright (c) 2010-2013 Baptiste Daroussin <bapt@FreeBSD.org>
# Copyright (c) 2010-2011 Julien Laffaye <jlaffaye@FreeBSD.org>
# Copyright (c) 2012-2021 Bryan Drewery <bdrewery@FreeBSD.org>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

## Pick the next package from the "ready to build" queue in pool/
## Then move the package to the "building" dir in building/
## This is only ran from 1 process
pkgqueue_get_next() {
	required_env pkgqueue_get_next PWD "${MASTER_DATADIR_ABS:?}/pool"
	[ $# -eq 2 ] || eargs pkgqueue_get_next pkgname_var porttesting_var
	local pkgname_var="$1"
	local porttesting_var="$2"
	local p _pkgname ret

	# CWD is MASTER_DATADIR/pool

	p=$(find ${POOL_BUCKET_DIRS:?} -type d -depth 1 -empty -print -quit) ||
	    err "${EX_SOFTWARE}" "pkgqueue_get_next: Failed to search queue"
	case "${p:+set}" in
	set)
		_pkgname=${p##*/}
		if ! rename "${p}" "${MASTER_DATADIR:?}/building/${_pkgname}" \
		    2>/dev/null; then
			# Was the failure from /unbalanced?
			case "${p}" in
			*"unbalanced/"*)
				# We lost the race with a child running
				# pkgqueue_balance_pool(). The file is already
				# gone and moved to a bucket. Try again.
				ret=0
				pkgqueue_get_next "$@" || ret=$?
				return ${ret}
				;;
			*)
				# Failure to move a balanced item??
				err 1 "pkgqueue_get_next: Failed to mv ${p} to ${MASTER_DATADIR}/building/${_pkgname}"
				;;
			esac
		fi
		# Update timestamp for buildtime accounting
		touch "${MASTER_DATADIR:?}/building/${_pkgname}"
		;;
	esac

	setvar "${pkgname_var}" "${_pkgname}"
	# XXX: All of this should be passed in the queue rather than determined
	# here.
	setvar "${porttesting_var}" $(get_porttesting "${_pkgname}")
}

# This is expected to run from the master process.
pkgqueue_job_done() {
	[ "$#" -eq 1 ] || eargs pkgqueue_job_done pkgname
	local pkgname="$1"

	rmdir "${MASTER_DATADIR:?}/building/${pkgname:?}"
}

pkgqueue_init() {
	mkdir -p "${MASTER_DATADIR:?}/building" \
		"${MASTER_DATADIR:?}/pool" \
		"${MASTER_DATADIR:?}/pool/unbalanced" \
		"${MASTER_DATADIR:?}/deps" \
		"${MASTER_DATADIR:?}/rdeps" \
		"${MASTER_DATADIR:?}/cleaning/deps" \
		"${MASTER_DATADIR:?}/cleaning/rdeps"
}

pkgqueue_contains() {
	required_env pkgqueue_contains PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 1 ] || eargs pkgqueue_contains pkgname
	local pkgname="$1"
	local pkg_dir_name

	pkgqueue_dir pkg_dir_name "${pkgname}"
	[ -d "deps/${pkg_dir_name}" ]
}

pkgqueue_add() {
	required_env pkgqueue_add PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 1 ] || eargs pkgqueue_add pkgname
	local pkgname="$1"
	local pkg_dir_name

	pkgqueue_dir pkg_dir_name "${pkgname}"
	mkdir -p "deps/${pkg_dir_name}"
}

pkgqueue_add_dep() {
	required_env pkgqueue_add_dep PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 2 ] || eargs pkgqueue_add_dep pkgname dep_pkgname
	local pkgname="$1"
	local dep_pkgname="$2"
	local pkg_dir_name

	pkgqueue_dir pkg_dir_name "${pkgname}"
	:> "deps/${pkg_dir_name}/${dep_pkgname}"
}

# Remove myself from the remaining list of dependencies for anything
# depending on this package. If clean_rdepends is set, instead cleanup
# anything depending on me and skip them.
pkgqueue_clean_rdeps() {
	required_env pkgqueue_clean_rdeps PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 2 ] || eargs pkgqueue_clean_rdeps clean_rdepends
	local pkgname="$1"
	local clean_rdepends="$2"
	local dep_dir dep_pkgname pkg_dir_name
	local deps_to_check deps_to_clean
	local rdep_dir rdep_dir_name

	rdep_dir="cleaning/rdeps/${pkgname}"

	# Exclusively claim the rdeps dir or return, another
	# pkgqueue_clean_queue() owns it or there were no reverse
	# deps for this package.
	pkgqueue_dir rdep_dir_name "${pkgname}"
	rename "rdeps/${rdep_dir_name}" "${rdep_dir}" 2>/dev/null ||
	    return 0

	# Cleanup everything that depends on my package
	# Note 2 loops here to avoid rechecking clean_rdepends every loop.
	case "${clean_rdepends:+set}" in
	set)
		# Recursively cleanup anything that depends on my package.
		for dep_dir in "${rdep_dir}"/*; do
			# May be empty if all my reverse deps are now skipped.
			case "${dep_dir}" in "${rdep_dir}/*") break ;; esac
			dep_pkgname="${dep_dir##*/}"

			# clean_pool() in common.sh will pick this up and add to SKIPPED
			echo "${dep_pkgname}"

			_pkgqueue_clean_queue ${dep_pkgname} "${clean_rdepends}"
		done
		;;
	"")
		for dep_dir in "${rdep_dir}/"*; do
			case "${dep_dir}" in
			"${rdep_dir}/*")
				deps_to_clean=
				deps_to_check=
				break
				;;
			esac
			dep_pkgname="${dep_dir##*/}"
			pkgqueue_dir pkg_dir_name "${dep_pkgname}"
			deps_to_check="${deps_to_check:+${deps_to_check} }deps/${pkg_dir_name}"
			deps_to_clean="${deps_to_clean:+${deps_to_clean} }deps/${pkg_dir_name}/${pkgname}"
		done
		case "${deps_to_clean:+set}${deps_to_check:+set}" in
		"") ;;
		*)
			# Remove this package from every package depending on
			# this. This is removing: deps/<dep_pkgname>/<this pkg>.
			# Note that this is not needed when recursively cleaning
			# as the entire /deps/<pkgname> for all my rdeps will
			# be removed.
			echo "${deps_to_clean}" | xargs rm -f || :

			# Look for packages that are now ready to build. They
			# have no remaining dependencies. Move them to
			# /unbalanced for later processing.
			echo "${deps_to_check}" |
			    xargs -J % \
			    find % -type d -maxdepth 0 -empty |
			    xargs -J % mv % "pool/unbalanced" || :
			;;
		# Errors are hidden as this has harmless races with other procs.
		esac 2>/dev/null
		;;
	esac

	rm -rf "${rdep_dir}" 2>/dev/null &

	return 0
}

# Remove my /deps/<pkgname> dir and any references to this dir in /rdeps/
pkgqueue_clean_deps() {
	required_env pkgqueue_clean_deps PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 2 ] || eargs pkgqueue_clean_deps clean_rdepends
	local pkgname="$1"
	local clean_rdepends="$2"
	local dep_dir rdep_pkgname pkg_dir_name
	local deps_to_check rdeps_to_clean
	local dir rdep_dir_name

	dep_dir="cleaning/deps/${pkgname}"

	# Exclusively claim the deps dir or return, another
	# pkgqueue_clean_queue() owns it.
	pkgqueue_dir pkg_dir_name "${pkgname}"
	rename "deps/${pkg_dir_name}" "${dep_dir}" 2>/dev/null ||
	    return 0

	# Remove myself from all my dependency rdeps to prevent them from
	# trying to skip me later

	for dir in "${dep_dir}"/*; do
		case "${dir}" in
		# empty dir
		"${dep_dir}/*")
			rdeps_to_clean=
			;;
		esac
		rdep_pkgname=${dir##*/}
		pkgqueue_dir rdep_dir_name "${rdep_pkgname}"
		rdeps_to_clean="${rdeps_to_clean:+${rdeps_to_clean} }rdeps/${rdep_dir_name}/${pkgname}"
	done

	case "${rdeps_to_clean:+set}" in
	set)
		echo "${rdeps_to_clean}" | xargs rm -f 2>/dev/null || :
		;;
	esac

	rm -rf "${dep_dir}" 2>/dev/null &

	return 0
}

_pkgqueue_clean_queue() {
	required_env _pkgqueue_clean_queue PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 2 ] || eargs _pkgqueue_clean_queue pkgname clean_rdepends
	local pkgname="$1"
	local clean_rdepends="$2"

	pkgqueue_clean_rdeps "${pkgname}" "${clean_rdepends}"

	# Remove this pkg from the needs-to-build list. It will not exist
	# if this build was sucessful. It only exists if pkgqueue_clean_queue is
	# being called recursively to skip items and in that case it will
	# not be empty.
	case "${clean_rdepends:+set}" in
	set) pkgqueue_clean_deps "${pkgname}" "${clean_rdepends}" ;;
	esac

	return 0
}

# This is expected to run from the child build process.
pkgqueue_clean_queue() {
	[ $# -eq 2 ] || eargs pkgqueue_clean_queue pkgname clean_rdepends
	local pkgname="$1"
	local clean_rdepends="$2"
	local oldpwd

	oldpwd=
	case "${PWD}" in
	"${MASTER_DATADIR_ABS:?}") ;;
	*)
		cd "${MASTER_DATADIR:?}"
		oldpwd="${OLDPWD}"
		;;
	esac

	ret="0"
	# Outputs skipped_pkgnames
	_pkgqueue_clean_queue "${pkgname}" "${clean_rdepends}" | sort -u ||
	    ret="$?"

	case "${clean_rdepends}" in
	"ignored") ;;
	*)
		pkgqueue_balance_pool || :
		;;
	esac

	case "${oldpwd:+set}" in
	set) cd "${oldpwd}" ;;
	esac

	return "${ret}"
}

pkgqueue_list() {
	required_env pkgqueue_list PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 0 ] || eargs pkgqueue_list

	find deps -type d -depth 2 | cut -d / -f 3
}

pkgqueue_prioritize() {
	[ "$#" -eq 2 ] || eargs pkgqueue_prioritize pkgname priority
	local pkgname="$1"
	local priority="$2"

	hash_set "pkgqueue_priority" "${pkgname}" "${priority}"
	list_add PKGQUEUE_PRIORITIES "${priority}"
}

pkgqueue_balance_pool() {
	required_env pkgqueue_balance_pool PWD "${MASTER_DATADIR_ABS:?}"
	local pkgname pkg_dir dep_count lock

	# Avoid running this in parallel, no need. Note that this lock is
	# not on the unbalanced/ dir, but only this function.
	# pkgqueue_clean_queue() writes to unbalanced/, pkgqueue_empty() reads
	# from it, and pkgqueue_get_next() moves from it.
	lock=.lock-pkgqueue_balance_pool
	mkdir "${lock}" 2>/dev/null || return 0

	if dirempty pool/unbalanced; then
		rmdir "${lock}"
		return 0
	fi

	# For everything ready-to-build...
	for pkg_dir in pool/unbalanced/*; do
		# May be empty due to racing with pkgqueue_get_next()
		case "${pkg_dir}" in
		"pool/unbalanced/*") break ;;
		esac
		pkgname="${pkg_dir##*/}"
		hash_remove "pkgqueue_priority" "${pkgname}" dep_count ||
		    dep_count=0
		# This races with pkgqueue_get_next(), just ignore failure
		# to move it.
		rename "${pkg_dir}" "pool/${dep_count}/${pkgname}" || :
	done 2>/dev/null
	# New files may have been added in unbalanced/ via
	# pkgqueue_clean_queue() due to not being locked.
	# These will be picked up in the next run.
	rmdir "${lock}"
}

# Create a pool of ready-to-build from the deps pool
pkgqueue_move_ready_to_pool() {
	required_env pkgqueue_move_ready_to_pool PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 0 ] || eargs pkgqueue_move_ready_to_pool

	# Create buckets to satisfy the dependency chain priorities.
	case "${PKGQUEUE_PRIORITIES:+set}" in
	set)
		POOL_BUCKET_DIRS="$(echo "${PKGQUEUE_PRIORITIES}" |
		    tr ' ' '\n' | LC_ALL=C sort -run |
		    paste -d ' ' -s -)"
		;;
	*)
		# If there are no buckets then everything to build will fall
		# into 0 as they depend on nothing and nothing depends on them.
		# I.e., pkg-devel in -ac or testport on something with no deps
		# needed.
		POOL_BUCKET_DIRS="0"
		;;
	esac

	# Create buckets after loading priorities in case of boosts.
	(
		if cd "${MASTER_DATADIR:?}/pool"; then
			mkdir ${POOL_BUCKET_DIRS:?}
		fi
	)

	# unbalanced is where everything starts at.  Items are moved in
	# pkgqueue_balance_pool based on their priority.
	POOL_BUCKET_DIRS="${POOL_BUCKET_DIRS:?} unbalanced"

	find deps -type d -depth 2 -empty |
	    xargs -J % mv % pool/unbalanced
	pkgqueue_balance_pool
}

# Remove all packages from queue sent in STDIN
pkgqueue_remove_many_pipe() {
	required_env pkgqueue_remove_many_pipe PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 0 ] || eargs pkgqueue_remove_many_pipe [pkgnames stdin]
	local pkgname

	while mapfile_read_loop_redir pkgname; do
		pkgqueue_find_all_pool_references "${pkgname}"
	done | while mapfile_read_loop_redir deppath; do
		echo "${deppath}"
		case "${deppath}" in
		deps/*/*/*|rdeps/*) ;;
		deps/*/*)
			msg_debug "Unqueueing ${COLOR_PORT}${deppath##*/}${COLOR_RESET}" >&2
			;;
		*) ;;
		esac
	done | xargs rm -rf
}

_pkgqueue_compute_rdeps() {
	required_env _pkgqueue_compute_rdeps PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 0 ] || eargs _pkgqueue_compute_rdeps
	local rdep_dir_name job dep_job

	find deps -mindepth 3 -maxdepth 3 -type f |
	    sed -e 's,deps/,,' |
	    cut -d / -f 2- |
	    awk -F/ '{print $1, $2}' |
	    while mapfile_read_loop_redir job dep_job; do
		pkgqueue_dir rdep_dir_name "${dep_job}"
		echo "${rdep_dir_name}/${job}"
	done
}

# Compute back references for quickly finding things to skip if this job
# fails.
pkgqueue_compute_rdeps() {
	required_env pkgqueue_compute_rdeps PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 0 ] || eargs pkgqueue_compute_rdeps
	local job rdep_dir_name dep

	# cd into rdeps to allow xargs mkdir to have more args.
	_pkgqueue_compute_rdeps |
	    sed -e 's,/[^/]*$,,' |
	    ( cd rdeps && xargs mkdir -p )
	_pkgqueue_compute_rdeps |
	    ( cd rdeps && xargs touch )
}

pkgqueue_remaining() {
	[ $# -eq 0 ] || eargs pkgqueue_remaining
	local -; set +e

	{
		# Find items in pool ready-to-build
		( cd "${MASTER_DATADIR:?}/pool"; find . -type d -depth 2 | \
		    sed -e 's,$, ready-to-build,' )
		# Find items in queue not ready-to-build.
		( cd "${MASTER_DATADIR:?}"; pkgqueue_list ) | \
		    sed -e 's,$, waiting-on-dependency,'
	} 2>/dev/null | sed -e 's,.*/,,'
	return 0
}

# Return directory name for given job
pkgqueue_dir() {
	[ $# -eq 2 ] || eargs pkgqueue_dir var_return dir
	local var_return="$1"
	local dir="$2"

	setvar "${var_return}" "$(printf "%.1s/%s" "${dir}" "${dir}")"
}

pkgqueue_sanity_check() {
	local always_fail=${1:-1}
	local crashed_packages dependency_cycles deps pkgname
	local failed_phase pwd dead_packages

	pwd="${PWD}"
	cd "${MASTER_DATADIR:?}"

	# If there are still packages marked as "building" they have crashed
	# and it's likely some poudriere or system bug
	crashed_packages=$( \
		find building -type d -mindepth 1 -maxdepth 1 | \
		sed -e "s,^building/,," | tr '\n' ' ' \
	)
	case "${crashed_packages:+set}" in
	set) err 1 "Crashed package builds detected: ${crashed_packages}" ;;
	esac

	# Check if there's a cycle in the need-to-build queue
	dependency_cycles=$(\
		find deps -mindepth 3 | \
		sed -e "s,^deps/[^/]*/,," -e 's:/: :' | \
		# Only cycle errors are wanted
		tsort 2>&1 >/dev/null | \
		sed -e 's/tsort: //' | \
		awk -f ${AWKPREFIX}/dependency_loop.awk \
	)

	case "${dependency_cycles:+set}" in
	set) err 1 "Dependency loop detected:"$'\n'"${dependency_cycles}" ;;
	esac

	dead_packages=$(pkgqueue_find_dead_packages)

	if [ ${always_fail} -eq 0 ]; then
		case "${dead_packages:+set}" in
		set)
			err 1 "Packages stuck in queue (depended on but not in queue): ${dead_packages}"
			;;
		esac
		cd "${pwd}"
		return 0
	fi

	case "${dead_packages:+set}" in
	set)
		failed_phase="stuck_in_queue"
		for pkgname in ${dead_packages}; do
			crashed_build "${pkgname}" "${failed_phase}"
		done
		cd "${pwd}"
		return 0
		;;
	esac

	# No cycle, there's some unknown poudriere bug
	err 1 "Unknown stuck queue bug detected. Please submit the entire build output to poudriere developers.
$(find ${MASTER_DATADIR}/building ${MASTER_DATADIR}/pool ${MASTER_DATADIR}/deps ${MASTER_DATADIR}/cleaning)"
}

pkgqueue_empty() {
	required_env pkgqueue_empty PWD "${MASTER_DATADIR_ABS:?}/pool"
	local pool_dir dirs
	local n

	case "${ALL_DEPS_DIRS-}" in
	"")
		ALL_DEPS_DIRS=$(find ${MASTER_DATADIR:?}/deps -mindepth 1 -maxdepth 1 -type d)
		;;
	esac

	dirs="${ALL_DEPS_DIRS} ${POOL_BUCKET_DIRS:?}"

	n=0
	# Check twice that the queue is empty. This avoids racing with
	# pkgqueue_clean_queue() and pkgqueue_balance_pool() moving files
	# between the dirs.
	while [ ${n} -lt 2 ]; do
		for pool_dir in ${dirs}; do
			if ! dirempty ${pool_dir}; then
				return 1
			fi
		done
		n=$((n + 1))
	done

	# Queue is empty
	return 0
}

# List deps from pkgnames in STDIN
pkgqueue_list_deps_pipe() {
	required_env pkgqueue_list_deps_pipe PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 0 ] || eargs pkgqueue_list_deps_pipe [pkgnames stdin]
	local pkgname FIND_ALL_DEPS

	unset FIND_ALL_DEPS
	while mapfile_read_loop_redir pkgname; do
		pkgqueue_list_deps_recurse "${pkgname}" | sort -u
	done | sort -u
}

pkgqueue_list_deps_recurse() {
	required_env pkgqueue_list_deps_recurse PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -ne 1 ] && eargs pkgqueue_list_deps_recurse pkgname
	local pkgname="$1"
	local dep_pkgname pkg_dir_name

	FIND_ALL_DEPS="${FIND_ALL_DEPS} ${pkgname}"

	#msg_debug "pkgqueue_list_deps_recurse ${pkgname}"

	pkgqueue_dir pkg_dir_name "${pkgname}"
	# Show deps/*/${pkgname}
	for pn in deps/"${pkg_dir_name}"/*; do
		dep_pkgname="${pn##*/}"
		case " ${FIND_ALL_DEPS} " in
			*" ${dep_pkgname} "*) continue ;;
		esac
		case "${pn}" in
		"deps/${pkg_dir_name}/*") break ;;
		esac
		echo "${dep_pkgname}"
		pkgqueue_list_deps_recurse "${dep_pkgname}"
	done
	echo "${pkgname}"
}

pkgqueue_find_dead_packages() {
	required_env pkgqueue_find_dead_packages PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 0 ] || eargs pkgqueue_find_dead_packages
	local dead_all dead_deps dead_top

	dead_all=$(mktemp -t dead_packages.all)
	dead_deps=$(mktemp -t dead_packages.deps)
	dead_top=$(mktemp -t dead_packages.top)
	find deps -mindepth 2 > "${dead_all}"
	# All packages in the queue
	cut -d / -f 3 "${dead_all}" | sort -u -o "${dead_top}"
	# All packages with dependencies
	cut -d / -f 4 "${dead_all}" | sed -e '/^$/d' | sort -u -o "${dead_deps}"
	# Find all packages only listed as dependencies (not in queue)
	comm -13 "${dead_top}" "${dead_deps}" || return 1
	rm -f "${dead_all}" "${dead_deps}" "${dead_top}" || :
}

pkgqueue_find_all_pool_references() {
	required_env pkgqueue_find_all_pool_references PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -ne 1 ] && eargs pkgqueue_find_all_pool_references pkgname
	local pkgname="$1"
	local rpn dep_pkgname rdep_dir_name pkg_dir_name dep_dir_name

	# Cleanup rdeps/*/${pkgname}
	pkgqueue_dir pkg_dir_name "${pkgname}"
	for rpn in deps/"${pkg_dir_name}"/*; do
		case "${rpn}" in
		# empty dir
		"deps/${pkg_dir_name}/*") break ;;
		esac
		dep_pkgname="${rpn##*/}"
		pkgqueue_dir rdep_dir_name "${dep_pkgname}"
		echo "rdeps/${rdep_dir_name}/${pkgname}"
	done
	echo "deps/${pkg_dir_name}"
	# Cleanup deps/*/${pkgname}
	pkgqueue_dir rdep_dir_name "${pkgname}"
	for rpn in rdeps/"${rdep_dir_name}"/*; do
		case "${rpn}" in
		# empty dir
		"rdeps/${rdep_dir_name}/*") break ;;
		esac
		dep_pkgname="${rpn##*/}"
		pkgqueue_dir dep_dir_name "${dep_pkgname}"
		echo "deps/${dep_dir_name}/${pkgname}"
	done
	echo "rdeps/${rdep_dir_name}"
}

pkgqueue_unqueue_existing_packages() {
	required_env pkgqueue_unqueue_existing_packages PWD "${MASTER_DATADIR_ABS:?}"
	local pn

	bset status "cleaning:"
	msg "Unqueueing existing packages"

	# Delete from the queue all that already have a current package.
	pkgqueue_list | while mapfile_read_loop_redir pn; do
		if [ -f "../packages/All/${pn}.${PKG_EXT}" ]; then
			echo "${pn}"
		fi
	done | pkgqueue_remove_many_pipe
}

# Delete from the queue orphaned build deps. This can happen if
# the specified-to-build ports have all their deps satisifed
# but one of their run deps has missing build deps packages which
# causes the build deps to be in the queue at this point.
pkgqueue_trim_orphaned_build_deps() {
	required_env pkgqueue_trim_orphaned_build_deps PWD "${MASTER_DATADIR_ABS:?}"
	local tmp port originspec pkgname

	case "${TRIM_ORPHANED_BUILD_DEPS}" in
	yes) ;;
	*) return 0 ;;
	esac
	if [ "${ALL}" -eq 1 ]; then
		return 0
	fi
	msg "Unqueueing orphaned build dependencies"
	tmp=$(mktemp -t queue)
	{
		listed_pkgnames
		# Pkg is a special case. It may not have been requested,
		# but it should always be rebuilt if missing.  The
		# originspec-pkgname lookup may fail if it wasn't
		# in the build queue.
		for port in ports-mgmt/pkg ports-mgmt/pkg-devel; do
			originspec_encode originspec "${port}" '' ''
			if shash_get originspec-pkgname "${port}" \
			    pkgname; then
				echo "${pkgname}"
			fi
		done
	} | pkgqueue_list_deps_pipe > "${tmp}"
	pkgqueue_list | sort -o "${tmp}.actual"
	comm -13 "${tmp}" "${tmp}.actual" | pkgqueue_remove_many_pipe
	rm -f "${tmp}" "${tmp}.actual"
}
