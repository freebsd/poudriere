set -e
. ./common.sh
set +e

# This test is not intended to be a comprehesive test of the tool that do_clone
# calls (cpdup). It is only intended to ensure do_clone flag handling does
# what is expected.

TMPDIR=$(mktemp -dt poudriere.do_clone)
export TMPDIR

setup_src() {
	if [ -n "${SRC_DIR}" ]; then
		rm -rf "${SRC_DIR}"
	fi
	SRC_DIR=$(mktemp -dt poudriere.do_clone)
	mkdir -p "${SRC_DIR}/deep/path/for/relative/testing"
	SRC_DIR="${SRC_DIR}/deep/for/relative/testing/path"
	mkdir -p "${SRC_DIR}/nested/path"
	echo "content" > "${SRC_DIR}/nested/file"
	echo "stuff" > "${SRC_DIR}/nested/blah"
}

# Basic test
{
	setup_src
	DST_DIR=$(mktemp -udt poudriere.do_clone)
	do_clone "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "do_clone"

	diff -urN "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "diff"
	rm -rf "${SRC_DIR}" "${DST_DIR}"
}

# Test not deleting files
{
	setup_src
	DST_DIR=$(mktemp -udt poudriere.do_clone)
	mkdir -p "${DST_DIR}"
	touch "${DST_DIR}/dont-delete-me"
	do_clone -x "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "do_clone"

	[ -f "${DST_DIR}/dont-delete-me" ]
	assert 0 $? "file should exist"

	diff -urN "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "diff"
	rm -rf "${SRC_DIR}" "${DST_DIR}"
}

# Test deleting files
{
	setup_src
	DST_DIR=$(mktemp -udt poudriere.do_clone)
	mkdir -p "${DST_DIR}"
	touch "${DST_DIR}/delete-me"
	do_clone_del "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "do_clone_del"

	[ -f "${DST_DIR}/delete-me" ]
	assert_not 0 $? "file should not exist"

	diff -urN "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "diff"
	rm -rf "${SRC_DIR}" "${DST_DIR}"
}

# Relative test
{
	setup_src
	DST_DIR=$(mktemp -udt poudriere.do_clone)
	do_clone -rx "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "do_clone"

	diff -urN "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "diff"
	rm -rf "${SRC_DIR}" "${DST_DIR}"
}

# Ignore based on .cpignore default (ignored)
{
	setup_src
	# Ignore the blah file
	cat > "${SRC_DIR}/.cpignore" <<-EOF
	blah
	EOF
	touch "${SRC_DIR}/blah"
	DST_DIR=$(mktemp -udt poudriere.do_clone)
	do_clone "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "do_clone"

	[ -f "${DST_DIR}/.cpignore" ]
	assert 0 $? ".cpignore should be copied"

	[ -f "${DST_DIR}/nested/blah" ]
	assert 0 $? "nested/blah should be copied"

	[ -f "${DST_DIR}/blah" ]
	assert 0 $? "blah should be copied"

	diff -urN "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "diff"

	diff -urN "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "diff"

	rm -rf "${SRC_DIR}" "${DST_DIR}"
}

# Ignore based on .cpignore
{
	setup_src
	# Ignore the blah file
	cat > "${SRC_DIR}/nested/.cpignore" <<-EOF
	blah
	EOF
	touch "${SRC_DIR}/blah"
	DST_DIR=$(mktemp -udt poudriere.do_clone)
	do_clone -x "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "do_clone"

	[ -f "${DST_DIR}/nested/.cpignore" ]
	assert_not 0 $? "nested/.cpignore should not be copied"

	[ -f "${DST_DIR}/nested/blah" ]
	assert_not 0 $? "nested/blah should not be copied"

	[ -f "${DST_DIR}/blah" ]
	assert 0 $? "blah should still be copied"


	diff -urN "${SRC_DIR}" "${DST_DIR}"
	# Fails due to missing blah/.cpignore files
	assert 1 $? "diff"

	rm -f "${SRC_DIR}/nested/blah"
	rm -f "${SRC_DIR}/nested/.cpignore"
	diff -urN "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "diff"

	rm -rf "${SRC_DIR}" "${DST_DIR}"
}

# Ignore based on .cpignore
{
	setup_src
	# Ignore the blah file
	cat > "${SRC_DIR}/nested/.cpignore" <<-EOF
	blah
	EOF
	touch "${SRC_DIR}/blah"
	DST_DIR=$(mktemp -udt poudriere.do_clone)
	do_clone -rx "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "do_clone"

	[ -f "${DST_DIR}/nested/.cpignore" ]
	assert_not 0 $? "nested/.cpignore should not be copied"

	[ -f "${DST_DIR}/nested/blah" ]
	assert_not 0 $? "nested/blah should not be copied"

	[ -f "${DST_DIR}/blah" ]
	assert 0 $? "blah should still be copied"


	diff -urN "${SRC_DIR}" "${DST_DIR}"
	# Fails due to missing blah/.cpignore files
	assert 1 $? "diff"

	rm -f "${SRC_DIR}/nested/blah"
	rm -f "${SRC_DIR}/nested/.cpignore"
	diff -urN "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "diff"

	rm -rf "${SRC_DIR}" "${DST_DIR}"
}

# Ignore based on .cpignore with -r with -x (redundant)
{
	setup_src
	# Ignore the blah file
	cat > "${SRC_DIR}/nested/.cpignore" <<-EOF
	blah
	EOF
	touch "${SRC_DIR}/blah"
	DST_DIR=$(mktemp -udt poudriere.do_clone)
	do_clone -rx "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "do_clone"

	[ -f "${DST_DIR}/nested/.cpignore" ]
	assert_not 0 $? "nested/.cpignore should not be copied"

	[ -f "${DST_DIR}/nested/blah" ]
	assert_not 0 $? "nested/blah should not be copied"

	[ -f "${DST_DIR}/blah" ]
	assert 0 $? "blah should still be copied"


	diff -urN "${SRC_DIR}" "${DST_DIR}"
	# Fails due to missing blah/.cpignore files
	assert 1 $? "diff"

	rm -f "${SRC_DIR}/nested/blah"
	rm -f "${SRC_DIR}/nested/.cpignore"
	diff -urN "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "diff"

	rm -rf "${SRC_DIR}" "${DST_DIR}"
}

# Ignore based on custom embedded .cpignore
{
	setup_src
	CPIGNORE=$(mktemp -ut poudriere.cpignore)
	# Ignore the blah file
	cat > "${SRC_DIR}/.cpignore" <<-EOF
	blah
	EOF
	touch "${SRC_DIR}/blah"
	DST_DIR=$(mktemp -udt poudriere.do_clone)
	do_clone -X ".cpignore" "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "do_clone"

	[ -f "${DST_DIR}/.cpignore" ]
	assert_not 0 $? ".cpignore should not be copied"

	[ -f "${DST_DIR}/blah" ]
	assert_not 0 $? "blah should not be copied"

	[ -f "${DST_DIR}/nested/blah" ]
	assert 0 $? "nested/blah should still be copied"

	diff -urN "${SRC_DIR}" "${DST_DIR}"
	# Fails due to missing blah/.cpignore files
	assert 1 $? "diff"

	rm -f "${SRC_DIR}/blah"
	rm -f "${SRC_DIR}/.cpignore"
	diff -urN "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "diff"

	rm -rf "${SRC_DIR}" "${DST_DIR}"
}

# Ignore based on custom .cpignore
{
	setup_src
	CPIGNORE=$(mktemp -ut poudriere.cpignore)
	# Ignore the blah file
	cat > "${CPIGNORE}" <<-EOF
	blah
	EOF
	touch "${SRC_DIR}/.cpignore"
	touch "${SRC_DIR}/blah"
	DST_DIR=$(mktemp -udt poudriere.do_clone)
	do_clone -X "${CPIGNORE}" "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "do_clone"

	[ -f "${DST_DIR}/.cpignore" ]
	assert 0 $? ".cpignore should still be copied"

	[ -f "${DST_DIR}/blah" ]
	assert_not 0 $? "blah should not be copied"

	[ -f "${DST_DIR}/nested/blah" ]
	assert_not 0 $? "nested/blah should not be copied"

	diff -urN "${SRC_DIR}" "${DST_DIR}"
	# Fails due to missing blah file
	assert 1 $? "diff"

	rm -f "${SRC_DIR}/blah"
	rm -f "${SRC_DIR}/nested/blah"
	diff -urN "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "diff"

	rm -rf "${SRC_DIR}" "${DST_DIR}" "${CPIGNORE}"
}

# Ignore based on custom .cpignore with -r
{
	setup_src
	CPIGNORE=$(mktemp -ut poudriere.cpignore)
	# Ignore the blah file
	cat > "${CPIGNORE}" <<-EOF
	blah
	EOF
	touch "${SRC_DIR}/.cpignore"
	touch "${SRC_DIR}/blah"
	DST_DIR=$(mktemp -udt poudriere.do_clone)
	do_clone -r -X "${CPIGNORE}" "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "do_clone"

	[ -f "${DST_DIR}/.cpignore" ]
	assert 0 $? ".cpignore should still be copied"

	[ -f "${DST_DIR}/blah" ]
	assert_not 0 $? "blah should not be copied"

	[ -f "${DST_DIR}/nested/blah" ]
	assert_not 0 $? "nested/blah should not be copied"

	diff -urN "${SRC_DIR}" "${DST_DIR}"
	# Fails due to missing blah file
	assert 1 $? "diff"

	rm -f "${SRC_DIR}/blah"
	rm -f "${SRC_DIR}/nested/blah"
	diff -urN "${SRC_DIR}" "${DST_DIR}"
	assert 0 $? "diff"

	rm -rf "${SRC_DIR}" "${DST_DIR}" "${CPIGNORE}"
}

rm -rf "${SRC_DIR}" "${DST_DIR}" "${CPIGNORE}" "${TMPDIR}"

exit 0
