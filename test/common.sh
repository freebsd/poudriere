echo "getpid: $$" >&2

cmp_cat() {
	local dest="$1"
	local tmp="$(TEMPDIR="${dest%/*}" mktemp -t ${dest##*/})"

	cat > "${tmp}"

	if ! cmp -s "${dest}" "${tmp}"; then
		mv -f "${tmp}" "${dest}"
	else
		rm -f "${tmp}"
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
cmp_cat "${POUDRIERE_ETC}/poudriere.d/poudriere.conf" << EOF
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
cmp_cat "${POUDRIERE_ETC}/poudriere.d/make.conf" << EOF
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
		[ "${arg%/}" = "/bin" ] && err 99 "Tried to rm /*"
	done

	command rm "$@"
}
