. common.sh

if [ "${SH-}" = "/bin/sh" ]; then
	echo "SKIP: Using stock sh" >&2
	exit 77
fi

for cmd in $(cat ${THISDIR}/../src/poudriere-sh/builtins-poudriere.def |
	awk '/^[^#]/ {print $NF}'); do
	assert "${cmd} is a shell builtin" "$(type "${cmd}")" \
		"${cmd} should be a builtin"
done
