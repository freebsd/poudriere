#! /bin/sh
export LC_ALL=C
set -e

SH_DIR=$1
if [ -z "${SH_DIR}" ]; then
	echo "Usage: $0 /usr/src/bin/sh" >&2
	exit 1
fi
DESTDIR=external/sh
rm -rf "${DESTDIR}"
mkdir -p "${DESTDIR}"
DESTDIR_REAL="$(realpath "${DESTDIR}")"
ORIG_PWD="${PWD}"
cd "${SH_DIR}"
export WITHOUT_TESTS=yes
export WITHOUT_AUTO_OBJ=yes
make cleanobj
make clean cleandepend
make depend
paths=$(make -V '${.PATH:N.*bltin*}'|xargs realpath)
{
	echo builtins.def
	echo mkbuiltins
	for src in *.h $(make -V SRCS); do
		if [ -f "${src}" ]; then
			echo "${PWD}/${src}"
		else
			for p in ${paths}; do
				[ -f "${p}/${src}" ] && echo "${p}/${src}" && break
			done
		fi
	done
} | sort -u | \
    tar -c -T - \
    --exclude bltin \
    --exclude builtins.c \
    --exclude builtins.h \
    -s ",.*/,,g" -f - | tar -C "${DESTDIR_REAL}" -xf -
cp -R "${SH_DIR}/bltin" "${DESTDIR_REAL}/bltin"
make clean cleandepend
cd "${ORIG_PWD}"

# Fix backwards compat for st_mtim
sed -i '' -e 's,[[:<:]]st_mtim[[:>:]],st_mtimespec,g' "${DESTDIR}/test.c"

git add -A "${DESTDIR}"
cat <<EOF
sh_SOURCES=		external/sh_compat/strchrnul.c \\
			external/sh_compat/utimensat.c \\
EOF
find "${DESTDIR}" -name '*.c'|sed -e 's,^,			,' -e 's,$, \\,'|sort
