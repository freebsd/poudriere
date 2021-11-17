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

: ${PKGQUEUE_JOB_SEP:=":"}

pkgqueue_job_decode() {
	local -; set +x -f -u
	[ $# -eq 3 ] || eargs pkgqueue_job_decode pkgqueue_job \
	    var_return_job_type var_return_job_name
	local pkgqueue_job="$1"
	local var_return_job_type="$2"
	local var_return_job_name="$3"
	local IFS __job_type __job_name

	IFS="${PKGQUEUE_JOB_SEP}"
	set -- ${pkgqueue_job}
	# type;name
	if [ $# -ne 2 ]; then
		err 1 "pkgqueue_job_decode '${pkgqueue_job}': wrong number of arguments (expected 2): $*"
	fi

	__job_type="$1"
	__job_name="$2"
	if [ -n "${var_return_job_type}" ]; then
		setvar "${var_return_job_type}" "${__job_type}"
	fi
	if [ -n "${var_return_job_name}" ]; then
		setvar "${var_return_job_name}" "${__job_name}"
	fi
}

pkgqueue_job_encode() {
	[ $# -eq 3 ] || eargs pkgqueue_job_encode var_return job_type job_name
	local var_return="$1"
	local job_type="$2"
	local job_name="$3"
	local __pkgqueue_job

	__pkgqueue_job="${job_type}${PKGQUEUE_JOB_SEP}${job_name}"
	setvar "${var_return}" "${__pkgqueue_job}"
}

## Pick the next package from the "ready to build" queue in pool/
## Then move the package to the "running" dir in running/
## This is only ran from 1 process
pkgqueue_get_next() {
	required_env pkgqueue_get_next PWD "${MASTER_DATADIR_ABS:?}/pool"
	[ "$#" -eq 2 ] || eargs pkgqueue_get_next job_type_var pkgname_var
	local pgn_job_type_var="$1"
	local pgn_pkgname_var="$2"
	local pgn_job_type pkgq_dir pgn_pkgname __pkgqueue_job ret

	# May need to try multiple times due to races and queued-for-order jobs
	while :; do
		pkgq_dir="$(find ${POOL_BUCKET_DIRS:?} \
		    -type d -depth 1 -empty -print -quit || :)"
		# No more eligible work!
		case "${pkgq_dir}" in
		"")
			pgn_job_type=
			pgn_pkgname=
			break
			;;
		esac
		ret=0
		_pkgqueue_job_start "${pkgq_dir}" || ret="$?"
		case "${ret}" in
		# Lost a race
		2) continue ;;
		# This job was queued for ordering only; No build is needed.
		3) continue ;;
		# This job is delayed
		4) continue ;;
		esac
		# Success or general error
		__pkgqueue_job="${pkgq_dir##*/}"
		pkgqueue_job_decode "${__pkgqueue_job}" pgn_job_type pgn_pkgname
		case "${__pkgqueue_job:+set}" in
		set) break ;;
		esac
	done

	setvar "${pgn_job_type_var}" "${pgn_job_type}"
	setvar "${pgn_pkgname_var}" "${pgn_pkgname}"
}

# This is expected to run from the master process.
pkgqueue_job_done() {
	[ "$#" -eq 2 ] || eargs pkgqueue_job_done job_type job_name
	local job_type="$1"
	local job_name="$2"
	local pkgqueue_job pkgq_dir delayed_pkgqueue_job
	local delayed_pkgname delayed_job_type

	pkgqueue_job_encode pkgqueue_job "${job_type}" "${job_name}"
	rmdir "${MASTER_DATADIR:?}/running/${pkgqueue_job:?}"

	# Should we undelay anything?
	if ! pkgqueue_job_is_mutually_exclusive "${pkgqueue_job}"; then
		return 0
	fi
	# This was a mutually exclusive package so it is
	# possible something else was delayed because of it.
	# Pick 1 delayed job to reinject.
	for pkgq_dir in ${MASTER_DATADIR:?}/pool/delayed/*; do
		case "${pkgq_dir}" in
		# Dir is empty
		"${MASTER_DATADIR}/pool/delayed/*") return 0 ;;
		esac
		delayed_pkgqueue_job="${pkgq_dir##*/}"
		pkgqueue_job_decode "${delayed_pkgqueue_job}" \
		    delayed_job_type delayed_pkgname
		msg_debug "pkgqueue_job_done: Undelaying ${delayed_job_type} for ${COLOR_PORT}${delayed_pkgname}${COLOR_RESET}"
		rename "${pkgq_dir}" \
		    "${MASTER_DATADIR:?}/pool/unbalanced/${delayed_pkgqueue_job:?}"
		break
	done
}

pkgqueue_job_is_mutually_exclusive() {
	[ $# -eq 1 ] || eargs pkgqueue_job_is_mutually_exclusive pkgqueue_job
	local pkgqueue_job="$1"
	local job_type job_name pkgname pkgbase pkgglob
	local -

	pkgqueue_job_decode "${pkgqueue_job}" job_type job_name
	case "${job_type}.${IN_TEST:-0}" in
	"build".*)
		pkgname="${job_name}"
		pkgbase="${pkgname%-*}"
		set -o noglob
		for pkgglob in ${MUTUALLY_EXCLUSIVE_BUILD_PACKAGES-}; do
			# shellcheck disable=SC2254
			case "${pkgbase}" in
			${pkgglob}) return 0 ;;
			esac
		done
		set +o noglob
		;;
	"run".*) ;;
	"test".1) ;;
	*) err "${EX_SOFTWARE}" "pkgqueue_job_is_mutually_exclusive: Unhandled job_type ${job_type}"
	esac
	return 1
}

_pkgqueue_job_start() {
	[ $# -eq 1 ] || eargs _pkgqueue_job_start pkgq_dir
	required_env _pkgqueue_job_start PWD "${MASTER_DATADIR_ABS:?}/pool"
	local pkgq_dir="$1"
	local job_name
	local job_type running_job running_jobs exclusive_jobs
	local pkgqueue_job running_dir

	pkgqueue_job="${pkgq_dir##*/}"
	pkgqueue_job_decode "${pkgqueue_job}" job_type job_name
	# We may race with pkgqueue_balance_pool()
	running_dir="${MASTER_DATADIR:?}/running/${pkgqueue_job:?}"
	if ! rename "${pkgq_dir}" "${running_dir}" 2>/dev/null; then
		# Was the failure from /unbalanced?
		case "${pkgq_dir}" in
		"unbalanced/"*)
			# We lost the race with a child running
			# pkgqueue_balance_pool(). The file is already
			# gone and moved to a bucket. Try again.
			return 2
			;;
		*)
			# Failure to move a balanced item??
			err 1 "_pkgqueue_job_start: Failed to mv ${pkgq_dir} to ${MASTER_DATADIR}/${running_dir#../}"
			;;
		esac
	fi
	# Do we actually need to run this job or was it just for ordering?
	if ! _pkgqueue_might_run "${pkgqueue_job}"; then
		msg_debug "Skipping ordering/inspection ${job_type} job ${COLOR_PORT}${job_name}${COLOR_RESET}"
		# Trim this from the queue...
		pkgqueue_job_done "${job_type}" "${job_name}"
		pkgqueue_clean_queue "${job_type}" "${job_name}" "" ||
		    err $? "_pkgqueue_job_start: Failure to clean queue for ${pkgqueue_job}"
		# ... and then try again.
		return 3
	fi

	# Should we delay this job?
	# Handle MUTUALLY_EXCLUSIVE_BUILD_PACKAGES
	if pkgqueue_job_is_mutually_exclusive "${pkgqueue_job}"; then
		running_jobs="$(pkgqueue_running)"
		# This new job wants to be mutually exclusive.  Are
		# there any others from the list running?
		for running_job in ${running_jobs}; do
			case "${running_job}" in
			"${pkgqueue_job}") continue ;;
			esac
			pkgqueue_job_is_mutually_exclusive "${running_job}" ||
			    continue
			exclusive_jobs="${exclusive_jobs:+${exclusive_jobs} }${running_job}"
		done
		case "${exclusive_jobs:+set}" in
		set)
			msg_debug "_pkgqueue_job_start: Delaying ${job_type} for ${COLOR_PORT}${job_name}${COLOR_RESET}: exclusive jobs running: ${COLOR_PORT}${exclusive_jobs}${COLOR_RESET}"
			rename "${running_dir}" \
			    "${MASTER_DATADIR:?}/pool/delayed/${pkgqueue_job:?}"
			return 4
			;;
		esac
	fi
}

pkgqueue_init() {
	mkdir -p "${MASTER_DATADIR:?}/running" \
		"${MASTER_DATADIR:?}/pool" \
		"${MASTER_DATADIR:?}/pool/unbalanced" \
		"${MASTER_DATADIR:?}/pool/delayed" \
		"${MASTER_DATADIR:?}/deps" \
		"${MASTER_DATADIR:?}/rdeps" \
		"${MASTER_DATADIR:?}/cleaning/deps" \
		"${MASTER_DATADIR:?}/cleaning/rdeps"
}

pkgqueue_contains() {
	required_env pkgqueue_contains PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 2 ] || eargs pkgqueue_contains job_type job_name
	local job_type="$1"
	local job_name="$2"
	local pkg_dir_name pkgqueue_job

	pkgqueue_job_encode pkgqueue_job "${job_type}" "${job_name}"
	pkgqueue_dir pkg_dir_name "${pkgqueue_job}"
	if [ ! -d "deps/${pkg_dir_name}" ]; then
		return 1
	fi
	_pkgqueue_might_run "${pkgqueue_job}"
}

# XXX: layer violation
_pkgqueue_might_run() {
	[ $# -eq 1 ] || eargs _pkgqueue_might_run pkgqueue_job
	local pkgqueue_job="$1"
	local job_type job_name pkgname PACKAGES

	pkgqueue_job_decode "${pkgqueue_job}" job_type job_name
	case "${job_type}.${IN_TEST:-0}" in
	"run".*) return 1 ;;
	"build".*) ;;
	"test".1) return 0 ;;
	*) err "${EX_SOFTWARE}" "_pkgqueue_might_run: Unhandled job_type ${job_type}" ;;
	esac
	pkgname="${job_name}"
	# XXX: Layer violation
	PACKAGES="${MASTER_DATADIR:?}/../packages"
	# No package - must build
	if [ ! -f "${PACKAGES:?}/All/${pkgname}.${PKG_EXT}" ]; then
		return 0
	fi
	# If this package has required shlibs we need to check it again later.
	# See build_pkg().
	if shash_exists pkgname-check_shlibs "${pkgname}"; then
		msg_debug "Might need to build ${COLOR_PORT}${pkgname}${COLOR_RESET} later for missing shlibs"
		return 0
	fi

	return 1
}

pkgqueue_add() {
	required_env pkgqueue_add PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 2 ] || eargs pkgqueue_add job_type job_name
	local job_type="$1"
	local job_name="$2"
	local pkg_dir_name pkgqueue_job

	pkgqueue_job_encode pkgqueue_job "${job_type}" "${job_name}"
	pkgqueue_dir pkg_dir_name "${pkgqueue_job}"
	mkdir -p "deps/${pkg_dir_name}"
}

pkgqueue_add_dep() {
	required_env pkgqueue_add_dep PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 4 ] || eargs pkgqueue_add_dep job_type job_name \
	    dep_job_type dep_job_name
	local job_type="$1"
	local job_name="$2"
	local dep_job_type="$3"
	local dep_job_name="$4"
	local pkg_dir_name pkgqueue_job dep_pkgqueue_job

	pkgqueue_job_encode pkgqueue_job "${job_type}" "${job_name}"
	pkgqueue_dir pkg_dir_name "${pkgqueue_job}"
	pkgqueue_job_encode dep_pkgqueue_job "${dep_job_type}" "${dep_job_name}"
	:> "deps/${pkg_dir_name}/${dep_pkgqueue_job}"
}

# Remove myself from the remaining list of dependencies for anything
# depending on this package. If clean_rdepends is set, instead cleanup
# anything depending on me and skip them.
pkgqueue_clean_rdeps() {
	required_env pkgqueue_clean_rdeps PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 2 ] || eargs pkgqueue_clean_rdeps pkgqueue_job clean_rdepends
	local pkgqueue_job="$1"
	local clean_rdepends="$2"
	local dep_dir pkg_dir_name dep_pkgqueue_job
	local deps_to_check deps_to_clean
	local rdep_dir rdep_dir_name

	rdep_dir="cleaning/rdeps/${pkgqueue_job}"

	# Exclusively claim the rdeps dir or return, another
	# pkgqueue_clean_queue() owns it or there were no reverse
	# deps for this package.
	pkgqueue_dir rdep_dir_name "${pkgqueue_job}"
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
			dep_pkgqueue_job="${dep_dir##*/}"

			# clean_pool() in common.sh will pick this up and add to SKIPPED
			echo "${dep_pkgqueue_job}"

			_pkgqueue_clean_queue "${dep_pkgqueue_job}" \
			    "${clean_rdepends}"
		done
		;;
	"")
		for dep_dir in "${rdep_dir}/"*; do
			case "${dep_dir}" in
			"${rdep_dir}/*")
				deps_to_check=
				deps_to_clean=
				break
				;;
			esac
			dep_pkgqueue_job="${dep_dir##*/}"
			pkgqueue_dir pkg_dir_name "${dep_pkgqueue_job}"
			deps_to_check="${deps_to_check} deps/${pkg_dir_name}"
			deps_to_clean="${deps_to_clean} deps/${pkg_dir_name}/${pkgqueue_job}"
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

# Remove my /deps/<pkgqueue_job> dir and any references to this dir in /rdeps/
pkgqueue_clean_deps() {
	required_env pkgqueue_clean_deps PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 2 ] || eargs pkgqueue_clean_deps pkgqueue_job clean_rdepends
	local pkgqueue_job="$1"
	local clean_rdepends="$2"
	local dep_dir rdep_pkgqueue_job pkg_dir_name
	local deps_to_check rdeps_to_clean
	local dir rdep_dir_name

	dep_dir="cleaning/deps/${pkgqueue_job}"

	# Exclusively claim the deps dir or return, another
	# pkgqueue_clean_queue() owns it.
	pkgqueue_dir pkg_dir_name "${pkgqueue_job}"
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
		rdep_pkgqueue_job="${dir##*/}"
		pkgqueue_dir rdep_dir_name "${rdep_pkgqueue_job}"
		rdeps_to_clean="${rdeps_to_clean:+${rdeps_to_clean} }rdeps/${rdep_dir_name}/${pkgqueue_job}"
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
	[ $# -eq 2 ] || eargs _pkgqueue_clean_queue pkgqueue_job clean_rdepends
	local pkgqueue_job="$1"
	local clean_rdepends="$2"
	local ret

	ret=0
	pkgqueue_clean_rdeps "${pkgqueue_job}" "${clean_rdepends}" || ret="$?"

	# Remove this pkg from the needs-to-build list. It will not exist
	# if this build was sucessful. It only exists if pkgqueue_clean_queue is
	# being called recursively to skip items and in that case it will
	# not be empty.
	case "${clean_rdepends:+set}" in
	set)
		pkgqueue_clean_deps "${pkgqueue_job}" "${clean_rdepends}" ||
		    ret="$?"
		;;
	esac

	return "${ret}"
}

# This is expected to run from the child build process.
pkgqueue_clean_queue() {
	[ "$#" -eq 3 ] || eargs pkgqueue_clean_queue job_type job_name clean_rdepends
	local job_type="$1"
	local job_name="$2"
	local clean_rdepends="${3-}"
	local -

	pkgqueue_job_encode pkgqueue_job "${job_type}" "${job_name}"
	set_pipefail
	# Outputs skipped_pkgnames
	in_reldir MASTER_DATADIR _pkgqueue_clean_queue "${pkgqueue_job}" \
	    "${clean_rdepends}" | sort -u ||
	    err "${EX_SOFTWARE}" "pkgqueue_clean_queue"
	in_reldir MASTER_DATADIR pkgqueue_balance_pool || :
}

pkgqueue_list() {
	required_env pkgqueue_list PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -le 1 ] || eargs pkgqueue_list '[want_job_type]'
	local want_job_type="${1-}"
	local pkgqueue_job job_type job_name

	find deps -type d -depth 2 | cut -d / -f 3 |
	    while mapfile_read_loop_redir pkgqueue_job; do
		pkgqueue_job_decode "${pkgqueue_job}" job_type job_name
		case "${want_job_type:+set}" in
		set)
			case "${job_type}" in
			"${want_job_type}") ;;
			*) continue ;;
			esac
			;;
		esac
		case "${want_job_type:+set}" in
		set)
			echo "${job_name}"
			;;
		*)
			echo "${pkgqueue_job}"
			;;
		esac
	done
}

pkgqueue_prioritize() {
	[ "$#" -eq 3 ] || eargs pkgqueue_prioritize job_type job_name priority
	local job_type="$1"
	local job_name="$2"
	local priority="$3"
	local pkgqueue_job

	pkgqueue_job_encode pkgqueue_job "${job_type}" "${job_name}"
	hash_set "pkgqueue_priority" "${pkgqueue_job}" "${priority}"
	list_add PKGQUEUE_PRIORITIES "${priority}"
}

pkgqueue_balance_pool() {
	required_env pkgqueue_balance_pool PWD "${MASTER_DATADIR_ABS:?}"
	local pkgq_dir pkgqueue_job dep_count lock

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

	# For everything ready-to-run...
	for pkgq_dir in pool/unbalanced/*; do
		# May be empty due to racing with pkgqueue_get_next()
		case "${pkgq_dir}" in
		"pool/unbalanced/*") break ;;
		esac
		pkgqueue_job="${pkgq_dir##*/}"
		hash_remove "pkgqueue_priority" "${pkgqueue_job}" dep_count ||
		    dep_count=0
		# This races with pkgqueue_get_next(), just ignore failure
		# to move it.
		rename "${pkgq_dir}" "pool/${dep_count}/${pkgqueue_job}" || :
	done 2>/dev/null
	# New files may have been added in unbalanced/ via
	# pkgqueue_clean_queue() due to not being locked.
	# These will be picked up in the next run.
	rmdir "${lock}"
}

# Create a pool of ready-to-run from the deps pool
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

pkgqueue_remove_many_pipe() {
	in_reldir MASTER_DATADIR _pkgqueue_remove_many_pipe "$@"
}

# Remove all packages from queue sent in STDIN
_pkgqueue_remove_many_pipe() {
	required_env _pkgqueue_remove_many_pipe PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 1 ] || eargs _pkgqueue_remove_many_pipe job_type [pkgnames stdin]
	local job_type="$1"
	local pkgname

	while mapfile_read_loop_redir pkgname; do
		_pkgqueue_find_all_pool_references "${job_type}" "${pkgname}"
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
		# Find items in pool ready-to-run
		( cd "${MASTER_DATADIR:?}/pool"; find . -type d -depth 2 | \
		    sed -e 's,$, ready-to-run,' )
		# Find items in queue not ready-to-run.
		( cd "${MASTER_DATADIR:?}"; pkgqueue_list ) |
		    sed -e 's,$, waiting-on-dependency,'
	} 2>/dev/null | sed -e 's,.*/,,'
	return 0
}

# Output a dependency file
pkgqueue_graph() {
	[ $# -eq 0 ] || eargs pkgqueue_graph

	(
		cd "${MASTER_DATADIR:?}"
		find deps -mindepth 2 -maxdepth 3 -type f -print |
		    awk -F / '{print $NF " " $(NF-1)}'
	)
}

pkgqueue_graph_dot() {
	[ $# -eq 0 ] || eargs pkgqueue_graph_dot
	echo "digraph Q {"
	pkgqueue_graph | tr '-' '_' | sort |
	    awk '{print "\t" "\"" $2 "\"" " -> " "\"" $1 "\"" ";"}'
	echo "}"
}

# Return directory name for given job
pkgqueue_dir() {
	[ $# -eq 2 ] || eargs pkgqueue_dir var_return pkgqueue_job
	local var_return="$1"
	local pkgqueue_job="$2"
	local job_type job_name

	pkgqueue_job_decode "${pkgqueue_job}" job_type job_name

	setvar "${var_return}" "$(printf "%.1s/%s" "${job_name:?}" \
	    "${pkgqueue_job}")"
}

pkgqueue_running() {
	find "${MASTER_DATADIR:?}/running" -type d -mindepth 1 -maxdepth 1 |
	    sed -e "s,^${MASTER_DATADIR:?}/running/,," | tr '\n' ' '
}

pkgqueue_sanity_check() {
	local always_fail=${1:-1}
	local crashed_packages dependency_cycles deps pkgqueue_job
	local failed_phase pwd dead_packages job_type job_name

	pwd="${PWD}"
	cd "${MASTER_DATADIR:?}"

	# If there are still packages marked as "running" they have crashed
	# and it's likely some poudriere or system bug
	crashed_packages="$(pkgqueue_running)"
	case "${crashed_packages:+set}" in
	set) err 1 "Crashed package builds detected: ${crashed_packages}" ;;
	esac

	# Check if there's a cycle in the need-to-run queue
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
		for pkgqueue_job in ${dead_packages}; do
			pkgqueue_job_decode "${pkgqueue_job}" job_type job_name
			crashed_build "${job_type}" "${job_name}" \
			    "${failed_phase}"
		done
		cd "${pwd}"
		return 0
		;;
	esac

	# No cycle, there's some unknown poudriere bug
	err 1 "Unknown stuck queue bug detected. Please submit the entire build output to poudriere developers.
$(find ${MASTER_DATADIR}/running ${MASTER_DATADIR}/pool ${MASTER_DATADIR}/deps ${MASTER_DATADIR}/cleaning)"
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
	[ $# -eq 1 ] || eargs pkgqueue_list_deps_pipe job_type [pkgnames stdin]
	local job_type="$1"
	local pkgname FIND_ALL_DEPS

	unset FIND_ALL_DEPS
	while mapfile_read_loop_redir pkgname; do
		pkgqueue_list_deps_recurse "${job_type}" "${pkgname}" | sort -u
	done | sort -u
}

pkgqueue_list_deps_recurse() {
	required_env pkgqueue_list_deps_recurse PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 2 ] || eargs pkgqueue_list_deps_recurse job_type pkgname
	local job_type="$1"
	local pkgname="$2"
	local pkgqueue_job dep_pkgqueue_job dep_job_type dep_pkgname pkg_dir_name

	pkgqueue_job_encode pkgqueue_job "${job_type}" "${pkgname}"
	#msg_debug "pkgqueue_list_deps_recurse ${pkgqueue_job}"
	FIND_ALL_DEPS="${FIND_ALL_DEPS:+${FIND_ALL_DEPS} }${pkgqueue_job}"
	pkgqueue_dir pkg_dir_name "${pkgqueue_job}"
	# Show deps/*/${pkgname}
	for pn in deps/"${pkg_dir_name}"/*; do
		dep_pkgqueue_job="${pn##*/}"
		case " ${FIND_ALL_DEPS} " in
			*" ${dep_pkgqueue_job} "*) continue ;;
		esac
		case "${pn}" in
		"deps/${pkg_dir_name}/*") break ;;
		esac
		pkgqueue_job_decode "${dep_pkgqueue_job}" dep_job_type \
		    dep_pkgname
		echo "${dep_pkgname}"
		pkgqueue_list_deps_recurse "${dep_job_type}" "${dep_pkgname}"
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
	in_reldir MASTER_DATADIR _pkgqueue_find_all_pool_references "$@"
}

_pkgqueue_find_all_pool_references() {
	required_env _pkgqueue_find_all_pool_references PWD "${MASTER_DATADIR_ABS:?}"
	[ $# -eq 2 ] || eargs _pkgqueue_find_all_pool_references job_type job_name
	local job_type="$1"
	local job_name="$2"
	local rpn dep_pkgqueue_job rdep_dir_name pkg_dir_name dep_dir_name
	local pkgqueue_job

	pkgqueue_job_encode pkgqueue_job "${job_type}" "${job_name}"
	# Cleanup rdeps/*/${pkgqueue_job}
	pkgqueue_dir pkg_dir_name "${pkgqueue_job}"
	for rpn in deps/"${pkg_dir_name}"/*; do
		case "${rpn}" in
		# empty dir
		"deps/${pkg_dir_name}/*") break ;;
		esac
		dep_pkgqueue_job="${rpn##*/}"
		pkgqueue_dir rdep_dir_name "${dep_pkgqueue_job}"
		echo "rdeps/${rdep_dir_name}/${pkgqueue_job}"
	done
	if [ -e "deps/${pkg_dir_name}" ]; then
		echo "deps/${pkg_dir_name}"
	fi
	# Cleanup deps/*/${pkgqueue_job}
	pkgqueue_dir rdep_dir_name "${pkgqueue_job}"
	for rpn in rdeps/"${rdep_dir_name}"/*; do
		case "${rpn}" in
		# empty dir
		"rdeps/${rdep_dir_name}/*") break ;;
		esac
		dep_pkgqueue_job="${rpn##*/}"
		pkgqueue_dir dep_dir_name "${dep_pkgqueue_job}"
		echo "deps/${dep_dir_name}/${pkgqueue_job}"
	done
	if [ -e "rdeps/${rdep_dir_name}" ]; then
		echo "rdeps/${rdep_dir_name}"
	fi
}

pkgqueue_unqueue_existing_packages() {
	required_env pkgqueue_unqueue_existing_packages PWD "${MASTER_DATADIR_ABS:?}"
	local pkgname pkgqueue_job

	bset status "cleaning:"
	msg "Unqueueing existing packages"

	# Delete from the queue all that already have a current package.
	pkgqueue_list "build" | while mapfile_read_loop_redir pkgname; do
		pkgqueue_job_encode pkgqueue_job "build" "${pkgname}"
		if ! _pkgqueue_might_run "${pkgqueue_job}"; then
			echo "${pkgname}"
		fi
	done | _pkgqueue_remove_many_pipe "build"
}

# We look at the queue and decide we do not need to BUILD ruby19 we just
# need to RUN it. So we can trim out stuff like this:
#   build:ruby19 run:gmake
#   build:ruby19 run:autoconf
#   build:ruby19 run:libyaml
# We must keep these though:
#   run:ruby19 run:libyaml

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
	} | pkgqueue_list_deps_pipe "run" > "${tmp}"
	pkgqueue_list "run" | sort -o "${tmp}.actual"
	comm -13 "${tmp}" "${tmp}.actual" | _pkgqueue_remove_many_pipe "build"
	rm -f "${tmp}" "${tmp}.actual"
}
