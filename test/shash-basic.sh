set -e
. ./common.sh
set +e

MASTERMNT=$(mktemp -d)

echo "Working on ${MASTERMNT}"
SHASH_VAR_PATH="${MASTERMNT}"
value=
assert_ret 0 shash_set blank key ""
assert_ret 0 shash_get blank key value
assert "" "${value}"
assert_ret 0 shash_unset blank key
value=
assert_ret 0 shash_set blank key $'\n'
assert_ret 0 shash_get blank key value
assert "" "${value}"
assert_ret_not 0 shash_remove pkgname-origin "pkg-1.7" value
assert_ret 0 shash_unset pkgname-origin "pkg-1.7"
assert_ret_not 0 shash_get pkgname-origin "pkg-1.7" value
assert_ret 0 shash_set pkgname-origin "pkg-1.7" "ports-mgmt/pkg"
assert_ret 0 shash_get pkgname-origin "pkg-1.7" value
assert_ret 0 shash_exists pkgname-origin "pkg-1.7"
assert_ret 1 shash_exists pkgname-origin "pkg-1.8"
assert "ports-mgmt/pkg" "${value}" "Removed value should match"
value=
assert_ret 0 shash_remove pkgname-origin "pkg-1.7" value
assert "ports-mgmt/pkg" "${value}" "Removed value should match"
value=
assert_ret_not 0 shash_get pkgname-origin "pkg-1.7" value

# Test globbing
{
	assert_ret_not 0 shash_get pkgname-origin "pkg-*" value
	assert_ret 0 shash_set pkgname-origin "pkg-1.7" "ports-mgmt/pkg"
	assert_ret 0 shash_get pkgname-origin "pkg-1.7" value
	value=
	assert_ret 0 shash_get pkgname-origin "pkg-*" value
	assert "ports-mgmt/pkg" "${value}" "Removed value should match"
	assert_ret 0 shash_set pkgname-origin "pkg-2.0" "ports-mgmt/pkg2"
	value=
	assert_ret 0 shash_get pkgname-origin "pkg-*" value
	assert "ports-mgmt/pkg ports-mgmt/pkg2" "${value}" "Globbing shash_get should match"
	assert_ret 0 shash_unset pkgname-origin "pkg-*"
	assert_ret_not 0 shash_get pkgname-origin "pkg-1.7" value
	assert_ret_not 0 shash_get pkgname-origin "pkg-2.0" value
	assert_ret_not 0 shash_get pkgname-origin "pkg-*" value

	assert_ret_not 0 shash_get pkgname-origin "notfound-*" value
	assert "" "${value}" "globbed missing value"

	assert_ret_not 0 shash_get pkgname-origin "*-notfound" value
	assert "" "${value}" "globbed missing value"
}

# Test shash_remove_var
{
	assert_ret 0 shash_set foo-origin "a" A
	assert_ret 0 shash_set foo-origin "b" B
	assert_ret 0 shash_set foo-origin "c" C
	assert_ret 0 shash_set foo-origin "d" D
	assert_ret 0 shash_get foo-origin "a" value
	assert "A" "${value}" "A value should match"
	assert_ret 0 shash_get foo-origin "b" value
	assert "B" "${value}" "B value should match"
	assert_ret 0 shash_get foo-origin "c" value
	assert "C" "${value}" "C value should match"
	assert_ret 0 shash_get foo-origin "d" value
	assert "D" "${value}" "D value should match"

	assert_ret 0 shash_remove_var foo-origin
	assert_ret_not 0 shash_get foo-origin "a" value
	assert_ret_not 0 shash_get foo-origin "b" value
	assert_ret_not 0 shash_get foo-origin "c" value
	assert_ret_not 0 shash_get foo-origin "d" value

	assert_ret_not 0 shash_get pkgname-origin "pkg-1.7" value
	assert_ret 0 shash_set pkgname-origin "pkg-1.7" "ports-mgmt/pkg"
	assert_ret 0 shash_get pkgname-origin "pkg-1.7" value
	assert "ports-mgmt/pkg" "${value}" "pkg should match afer shash_remove_var"
}

# shash_read_mapfile on nonexistent var-key should fail
{
	handle=unset
	assert_ret_not 0 shash_read_mapfile nonexistent key handle
	assert "unset" "${handle}"
}

# shash_read on nonexistent var-key should fail
{
	TMP="$(mktemp -ut shash_read)"
	assert_ret_not 0 shash_read nonexistent key > "${TMP}"
	assert_ret_not 0 test -s "${TMP}"
	rm -f "${TMP}"
}

# shash_get to stdout, basis for some of the streaming handling.
{
	assert_true shash_set test key "value"
	TMP="$(mktemp -ut shash-basic.stdout)"
	assert_true shash_get test key - > "${TMP}"
	assert_file - "${TMP}" <<-EOF
	value
	EOF
}

# shash_read_mapfile on existing var-key should pass
{

	assert_ret 0 shash_set test key "value"
	handle=unset
	assert_ret 0 shash_read_mapfile test key handle
	assert_not "unset" "${handle}"
	value=unset
	assert_ret 0 mapfile_read "${handle}" value
	assert "value" "${value}"
	assert_ret_not 0 mapfile_read "${handle}" value
	assert_ret 0 mapfile_close "${handle}"
}

# Test write / read
{
	shash_write pkgmetadata "annotations" <<-EOF
	1
	2 3
	3 4 5
	4 5 6 7
	EOF
	assert "0" "$?" "shash_write pkgmetadata annotations"

	lines=1
	shash_read pkgmetadata "annotations" |
	(
		set -e
		while mapfile_read_loop_redir value1 rest; do
			assert "${lines}" "${value1}" "shash_read pkgmetadata annotations line $lines bad value1"
			case "${value1}" in
			1) assert "" "${rest}" "shash_read pkgmetadata annotations line $lines bad" ;;
			2) assert "3" "${rest}" "shash_read pkgmetadata annotations line $lines bad" ;;
			3) assert "4 5" "${rest}" "shash_read pkgmetadata annotations line $lines bad" ;;
			4) assert "5 6 7" "${rest}" "shash_read pkgmetadata annotations line $lines bad" ;;
			*) assert 0 1 "shash_read pkgmetadata annotations found unexpected value: '${value1}${rest:+ ${rest}}'" ;;
			esac
			lines=$((lines + 1))
		done
		exit "${lines}"
	)
	assert 5 "$?" "shash_read pkgmetadata annotations ret != lines+1"

	lines=1
	assert_ret 0 shash_read_mapfile pkgmetadata "annotations" handle
	while mapfile_read "${handle}" value1 rest; do
		assert "${lines}" "${value1}" "shash_read_mapfile pkgmetadata annotations line $lines bad value1"
		case "${value1}" in
		1) assert "" "${rest}" "shash_read_mapfile pkgmetadata annotations line $lines bad" ;;
		2) assert "3" "${rest}" "shash_read_mapfile pkgmetadata annotations line $lines bad" ;;
		3) assert "4 5" "${rest}" "shash_read_mapfile pkgmetadata annotations line $lines bad" ;;
		4) assert "5 6 7" "${rest}" "shash_read_mapfile pkgmetadata annotations line $lines bad" ;;
		*) assert 0 1 "shash_read_mapfile pkgmetadata annotations found unexpected value: '${value1}${rest:+ ${rest}}'" ;;
		esac
		lines=$((lines + 1))
	done
	assert 5 "$lines" "shash_read_mapfile pkgmetadata annotations lines"
	assert_ret 0 mapfile_close "${handle}"

}

# Test blank shash_set does not return newline in shash_read / shash_get
{
	shash_set pkgmetadata "annotations-blank1" "bogus"
	shash_set pkgmetadata "annotations-blank1" ""
	assert "0" "$?" "shash_set pkgmetadata annotations-blank1"

	lines=0
	shash_read pkgmetadata "annotations-blank1" |
	(
		set -e
		while mapfile_read_loop_redir value1 rest; do
			assert "" "${value1}"
			lines=$((lines + 1))
		done
		exit "${lines}"
	)
	assert 1 "$?" "shash_read pkgmetadata annotations-blank1 should read 1 line. lines=$?"

	assert_ret 0 shash_exists pkgmetadata "annotations-blank1"

	value=unset
	assert_ret 0 shash_get pkgmetadata "annotations-blank1" value
	assert "empty" "${value:-empty}"
}

# Test blank -n shash_write does not return newline in shash_read / shash_get
{
	shash_set pkgmetadata "annotations-blank2" "bogus"
	echo -n | shash_write pkgmetadata "annotations-blank2"
	assert "0" "$?" "shash_write pkgmetadata annotations-blank2"
	assert_ret 0 shash_exists pkgmetadata "annotations-blank2"
	value=
	assert_ret 0 shash_get pkgmetadata "annotations-blank2" value
	assert "" "${value}"

	lines=0
	shash_read pkgmetadata "annotations-blank2" |
	(
		set -e
		while mapfile_read_loop_redir value1 rest; do
			assert "" "${value1}"
			lines=$((lines + 1))
		done
		exit "${lines}"
	)
	assert 0 "$?" "shash_read pkgmetadata annotations-blank2 should not read any lines. lines=$?"

	lines=0
	assert_ret 0 shash_read_mapfile pkgmetadata "annotations-blank2" handle
	while mapfile_read "${handle}" value1 rest; do
		lines=$((lines + 1))
	done
	assert 0 "$lines" "shash_read_mapfile pkgmetadata annotations-blank2 should not read any lines. lines=$lines"
	assert_ret 0 mapfile_close "${handle}"

	assert_ret 0 shash_exists pkgmetadata "annotations-blank2"

	value=unset
	assert_ret 0 shash_get pkgmetadata "annotations-blank2" value
	assert "empty" "${value:-empty}"
}

# Test blank stdin to shash_write does not return newline in shash_read / shash_get
{
	shash_set pkgmetadata "annotations-blank3" "bogus"
	: | shash_write pkgmetadata "annotations-blank3"
	assert "0" "$?" "shash_write pkgmetadata annotations-blank3"
	assert_ret 0 shash_exists pkgmetadata "annotations-blank3"
	value=
	assert_ret 0 shash_get pkgmetadata "annotations-blank3" value
	assert "" "${value}"

	lines=0
	shash_read pkgmetadata "annotations-blank3" |
	(
		set -e
		while mapfile_read_loop_redir value1 rest; do
			assert "" "${value1}"
			lines=$((lines + 1))
		done
		exit "${lines}"
	)
	assert 0 "$?" "shash_read pkgmetadata annotations-blank3 should not read any lines. lines=$?"

	lines=0
	assert_ret 0 shash_read_mapfile pkgmetadata "annotations-blank3" handle
	while mapfile_read "${handle}" value1 rest; do
		lines=$((lines + 1))
	done
	assert 0 "$lines" "shash_read_mapfile pkgmetadata annotations-blank3 should not read any lines. lines=$lines"
	assert_ret 0 mapfile_close "${handle}"

	assert_ret 0 shash_exists pkgmetadata "annotations-blank3"

	value=unset
	assert_ret 0 shash_get pkgmetadata "annotations-blank3" value
	assert "empty" "${value:-empty}"
}

# Test blank write with newline to shash_write *does* return newline
# in shash_read / shash_get
{
	shash_set pkgmetadata "annotations-blank4" "bogus"
	echo | shash_write pkgmetadata "annotations-blank4"
	assert "0" "$?" "shash_write pkgmetadata annotations-blank4"
	assert_ret 0 shash_exists pkgmetadata "annotations-blank4"
	value=
	assert_ret 0 shash_get pkgmetadata "annotations-blank4" value
	assert "" "${value}"

	lines=0
	shash_read pkgmetadata "annotations-blank4" |
	(
		set -e
		while mapfile_read_loop_redir value1 rest; do
			assert "" "${value1}"
			lines=$((lines + 1))
		done
		exit "${lines}"
	)
	assert 1 "$?" "shash_read pkgmetadata annotations-blank4 should read 1 line. lines=$?"

	lines=0
	assert_ret 0 shash_read_mapfile pkgmetadata "annotations-blank4" handle
	while mapfile_read "${handle}" value1 rest; do
		lines=$((lines + 1))
	done
	assert 1 "$lines" "shash_read_mapfile pkgmetadata annotations-blank4 should read 1 line. lines=$lines"
	assert_ret 0 mapfile_close "${handle}"

	assert_ret 0 shash_exists pkgmetadata "annotations-blank4"

	value=unset
	assert_ret 0 shash_get pkgmetadata "annotations-blank4" value
	assert "empty" "${value:-empty}"
}

# shash_write with tee
{

	assert_ret 1 shash_exists description "pkg-foo"
	TMP="$(mktemp -ut shash_tee)"
	cat > "${TMP}" <<-EOF
	This is a test package description for pkg-foo.

	This package is used for testing shash_tee.
	WWW: www.test.com
	EOF
	cp -f "${TMP}" "${TMP}.save" # XXX: assert_file deletes currently
	cat "${TMP}" | assert_ret 0 shash_write -T description "pkg-foo" > "${TMP}.3"
	assert 0 "$?" "shash_tee"
	assert_file "${TMP}" "${TMP}.3"
	mv -f "${TMP}.save" "${TMP}" # XXX: assert_file deletes currently
	assert_ret 0 shash_read description "pkg-foo" > "${TMP}.2"
	assert_file "${TMP}" "${TMP}.2"
	rm -f "${TMP}" "${TMP}.2" "${TMP}.3"
	assert_ret 0 shash_unset description "pkg-foo"
}

# shash_tee with just newline is valid; newline should be trimmed
{

	assert_ret 1 shash_exists description "pkg-foo"
	TMP="$(mktemp -ut shash_tee)"
	echo > "${TMP}"
	assert_ret 0 test -s  "${TMP}"
	cp -f "${TMP}" "${TMP}.save" # XXX: assert_file deletes currently
	cat "${TMP}" | assert_ret 0 shash_write -T description "pkg-foo" > "${TMP}.3"
	assert 0 "$?" "shash_tee"
	assert_file "${TMP}" "${TMP}.3"
	mv -f "${TMP}.save" "${TMP}" # XXX: assert_file deletes currently
	assert_ret 0 shash_read description "pkg-foo" > "${TMP}.2"
	assert_file "${TMP}" "${TMP}.2"
	rm -f "${TMP}" "${TMP}.2" "${TMP}.3"
	assert_ret 0 shash_unset description "pkg-foo"
}

# shash_tee with empth data is still valid
{

	assert_ret 1 shash_exists description "pkg-foo"
	TMP="$(mktemp -ut shash_tee)"
	: > "${TMP}"
	assert_ret 1 test -s  "${TMP}"
	cp -f "${TMP}" "${TMP}.save" # XXX: assert_file deletes currently
	cat "${TMP}" | assert_ret 0 shash_write -T description "pkg-foo" > "${TMP}.3"
	assert 0 "$?" "shash_tee"
	assert_file "${TMP}" "${TMP}.3"
	mv -f "${TMP}.save" "${TMP}" # XXX: assert_file deletes currently
	assert_ret 0 shash_read description "pkg-foo" > "${TMP}.2"
	assert_file "${TMP}" "${TMP}.2"
	rm -f "${TMP}" "${TMP}.2" "${TMP}.3"
	assert_ret 0 shash_unset description "pkg-foo"
}

rm -rf "${MASTERMNT}"
exit 0
