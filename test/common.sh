echo "getpid: $$" >&2

# Duplicated from src/share/poudriere/util.sh because it is too early to
# include that file.
write_cmp() {
	local dest="$1"
	local tmp ret

	ret=0
	tmp="$(TMPDIR="${dest%/*}" mktemp -t ${dest##*/})" ||
		err $? "write_cmp unable to create tmpfile in ${dest%/*}"
	cat > "${tmp}" || ret=$?
	if [ "${ret}" -ne 0 ]; then
		rm -f "${tmp}"
		return "${ret}"
	fi

	if ! cmp -s "${dest}" "${tmp}"; then
		rename "${tmp}" "${dest}"
	else
		unlink "${tmp}"
	fi
}


CMD="${0##*/}"
IN_TEST=1
SCRIPTPATH="${SCRIPTPREFIX}/${CMD}"
: ${BASEFS:=/var/tmp/poudriere/test}
POUDRIERE_ETC="${BASEFS}/etc"

: ${DISTFILES_CACHE:=$(mktemp -dt distfiles)}

mkdir -p ${POUDRIERE_ETC}/poudriere.d ${POUDRIERE_ETC}/run
rm -f "${POUDRIERE_ETC}/poudriere.conf"
write_cmp "${POUDRIERE_ETC}/poudriere.d/poudriere.conf" << EOF
NO_ZFS=yes
BASEFS=${BASEFS}
DISTFILES_CACHE=${DISTFILES_CACHE}
USE_TMPFS=all
USE_PROCFS=no
USE_FDESCFS=no
NOLINUX=yes
# jail -c options
NO_LIB32=yes
NO_SRC=yes
SHARED_LOCK_DIR="${POUDRIERE_ETC}/run"
EOF
write_cmp "${POUDRIERE_ETC}/poudriere.d/make.conf" << EOF
DEFAULT_VERSIONS+=	ssl=base
EOF

: ${VERBOSE:=1}
: ${PARALLEL_JOBS:=2}

msg() {
	echo "$@"
}
msg_debug() {
	if [ ${VERBOSE} -le 1 ]; then
		msg_debug() { }
		return 0
	fi
	msg "[DEBUG] $@" >&2
}

msg_warn() {
	msg "[WARN] $@" >&2
}

msg_dev() {
	if [ ${VERBOSE} -le 2 ]; then
		msg_dev() { }
		return 0
	fi
	msg "[DEV] $@" >&2
}

assert() {
	[ $# -eq 3 ] || eargs assert expected actual msg
	local expected="$(echo "$1" | cat -ev)"
	local actual="$(echo "$2" | cat -ev)"
	local msg="$3"

	: ${EXITVAL:=0}

	EXITVAL=$((${EXITVAL:-0} + 1))

	if [ "${actual}" != "${expected}" ]; then
		aecho "${msg}: expected: '${expected}', actual: '${actual}'"
		exit ${EXITVAL}
	fi

	return 0

}

assert_not() {
	[ $# -eq 3 ] || eargs assert_not notexpected actual msg
	local notexpected="$(echo "$1" | cat -ev)"
	local actual="$(echo "$2" | cat -ev)"
	local msg="$3"

	: ${EXITVAL:=0}

	EXITVAL=$((${EXITVAL:-0} + 1))

	if [ "${actual}" = "${notexpected}" ]; then
		aecho "${msg}: notexpected: '${notexpected}', actual: '${actual}'"
		exit ${EXITVAL}
	fi

	return 0

}

assert_ret() {
	local expected="$1"
	local ret

	shift

	ret=0
	"$@" || ret=$?
	assert ${expected} ${ret} "$*"
}

aecho() {
	echo "$@" >&2
}

rm() {
	local arg

	for arg in "$@"; do
		[ "${arg}" = "/" ] && err 99 "Tried to rm /"
		[ "${arg%/}" = "/COPYRIGHT" ] && err 99 "Tried to rm /*"
		[ "${arg%/}" = "/bin" ] && err 99 "Tried to rm /*"
	done

	command rm "$@"
}

err() {
	local status="$1"
	shift
	echo "Error: $@" >&2
	exit ${status}
}
