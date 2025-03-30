. ./common.sh

if [ "${SH-}" = "/bin/sh" ]; then
	echo "SKIP: Using stock sh" >&2
	exit 77
fi

for cmd in $(cat ${THISDIR}/../src/poudriere-sh/builtins-poudriere.def |
	awk '/^[^#]/ {print $NF}'); do
	case ${cmd} in
	# Overridden to allow a hook
	mapfile_close) continue ;;
	# Overridden to make cleanup simpler
	mktemp|_mktemp) continue ;;
	# Overridden to capture some errors
	pwait) continue ;;
	# Overridden for rm -rf / safety
	rm) continue ;;
	# Overridden to add Poudriere into the title
	setproctitle) continue ;;
	# Overridden to hide errors
	unlink) continue ;;
	esac
	assert "${cmd} is a shell builtin" "$(type "${cmd}")" \
		"${cmd} should be a builtin"
done
