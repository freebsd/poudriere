. ./common.sh

if ! which shellcheck >/dev/null 2>&1; then
	msg_warn "Skipping as shellcheck is not found"
	exit 77
fi

BASEDIR="${am_abs_top_srcdir:?}/src/share/poudriere/"

FILES="$({
	find "${BASEDIR:?}" -name '*.sh' |
	sed -e "s#^${BASEDIR:?}##" |
	tr '\n' ' '
})"
PASSING="
include/hash.sh
include/parallel.sh
include/shared_hash.sh
include/util.sh
"
set_test_contexts - '' '' <<-EOF
FILE	${FILES}
EOF

while get_test_context; do
	exp=
	case " $(echo "${PASSING}" | tr '\n' ' ') " in
	*" ${FILE:?} "*)
		exp=assert_true
		;;
	*)
		# Expected to fail for now
		exp=assert_false
		;;
	esac
	"${exp}" shellcheck -s ksh --norc "${BASEDIR:?}${FILE:?}"
done
