set -e
. ./common.sh
set +e

set_pipefail

JAILED=$(sysctl -n security.jail.jailed 2>/dev/null || echo 0)

LINES=20

test_cleanup() {
	if [ -n "${TMP}" ]; then
		rm -rf "${TMP}"
		unset TMP
	fi
	if [ -n "${TMP2}" ]; then
		rm -rf "${TMP2}"
		unset TMP2
	fi
}

writer() {
	local stdout="$1"
	local type="$2"

	case ${type} in
	pipe) exec > "${stdout}" ;;
	mapfile)
		mapfile out "${stdout}" "we"
		;;
	esac
	n=0
	until [ $n -eq ${LINES} ]; do
		case ${type} in
		pipe) echo "${n}\\" ;;
		mapfile) mapfile_write "${out}" -- "${n}\\" ;;
		esac
		n=$((n + 1))
	done
	if [ "${type}" = "mapfile" ]; then
		mapfile_close "${out}"
	fi
}

{
	TMP=$(mktemp -u)
	assert_ret_not 0 [ -e "${TMP}" ]
	assert_ret_not 0 expect_error_on_stderr mapfile handle "${TMP}" "re"
	rm -f "${TMP}"
}

{
	TMP=$(mktemp -u)
	TMP2=$(mktemp -u)
	TMP3=$(mktemp -u)
	assert_false expect_error_on_stderr mapfile file_read "${TMP}" "re"
	:> "${TMP}"
	assert_true mapfile file_read "${TMP}" "re"
	assert_false test -r "${TMP2}"
	assert_true mapfile file_write1 "${TMP2}" "ae"
	assert_true test -r "${TMP2}"
	assert_true mapfile file_write2 "${TMP3}" "we"
	assert_true test -r "${TMP3}"
	assert_true mapfile_close "${file_write2}"
	assert_true mapfile_close "${file_write1}"
	assert_true mapfile_close "${file_read}"
	rm -f "${TMP}" "${TMP2}" "${TMP3}"
}

# non-builtin can still do writing to multiple files concurrently. Just
# not reading.
{
	TMP=$(mktemp -u)
	TMP2=$(mktemp -u)
	TMP3=$(mktemp -u)
	assert_true cat > "${TMP}" <<-EOF
	file_read0
	read0
	EOF
	assert_true cat > "${TMP2}" <<-EOF
	TMP2 start
	EOF
	assert_true cat > "${TMP3}" <<-EOF
	TMP3 start
	EOF
	assert_true mapfile file_read "${TMP}" "re"
	assert_true mapfile file_write1 "${TMP2}" "ae"
	assert_true mapfile file_write2 "${TMP3}" "we"
	assert_false catch_err mapfile_read "${file_write2}" blah
	assert_true mapfile_write "${file_write1}" "file_write1"
	assert_true mapfile_write "${file_write2}" "file_write2"
	assert_true mapfile_read "${file_read}" line
	assert "file_read0" "${line}"
	assert_true mapfile_write "${file_write1}" "data1"
	assert_true mapfile_write "${file_write2}" "data2" "data3"
	assert_true mapfile_write "${file_write2}" "data4" "data5 data6"
	assert_true mapfile_read "${file_read}" line
	assert "read0" "${line}"
	assert_false mapfile_read "${file_read}" line
	assert_true mapfile_close "${file_read}"
	assert_true mapfile_close "${file_write1}"
	assert_true mapfile_close "${file_write2}"
	assert_file - "${TMP}" <<-EOF
	file_read0
	read0
	EOF

	assert_file - "${TMP2}" <<-EOF
	TMP2 start
	file_write1
	data1
	EOF

	assert_file - "${TMP3}" <<-EOF
	file_write2
	data2 data3
	data4 data5 data6
	EOF

	rm -f "${TMP}" "${TMP2}" "${TMP3}"
}

{
	echo blah | {
		n=0
		while mapfile_read_loop - line; do
			assert "blah" "${line}"
			n=$((n + 1))
		done
		assert 1 "${n}"
	}
	assert 0 "$?"
}

if mapfile_builtin; then
# Test pipes
{
	[ -f /nonexistent ]
	assert_not 0 $? "/nonexistent should not exist"
	mapfile foo "/nonexistent" 2>/dev/null
	assert_not 0 $? "mapfile should fail on nonexistent file"
	assert '' "${foo}" "mapfile should not return a handle on nonexistent file"
	mapfile_close "random" 2>/dev/null
	assert_not 0 $? "mapfile_close on unopened handle should not succeed"

	TMP=$(mktemp -ut mapfile)
	mkfifo "${TMP}"
	spawn_job writer "${TMP}" pipe

	mapfile handle1 "${TMP}"
	assert 0 $? "mapfile handle1 should succeed"
	assert_not '' "${handle1}" "mapfile handle1 should return a handle"

	TMP2=$(mktemp -ut mapfile)
	mkfifo "${TMP2}"
	spawn_job writer "${TMP2}" mapfile

	mapfile handle2 "${TMP2}"
	assert 0 $? "mapfile handle2 should succeed"
	assert_not '' "${handle2}" "mapfile handle2 should return a handle"

	n=0
	until [ $n -eq ${LINES} ]; do
		mapfile_read "${handle1}" line
		assert 0 $? "mapfile_read handle1 should succeed line $n"
		assert "${n}\\" "$line" "mapfile_read handle1 should match line $n"

		mapfile_read "${handle2}" line
		assert 0 $? "mapfile_read handle2 should succeed line $n"
		assert "${n}\\" "$line" "mapfile_read handle2 should match line $n"

		n=$((n + 1))
	done

	mapfile_close "${handle1}"
	assert 0 $? "mapfile_close handle1 should succeed"

	mapfile_close "${handle2}"
	assert 0 $? "mapfile_close handle2 should succeed"

	unset line
	mapfile_read "${handle1}" line 2>/dev/null
	assert_not 0 $? "mapfile_read on a closed handle should not succeed"
	assert '' "$line" "mapfile_read on a closed handle should not modify line"

	kill_all_jobs || :
	rm -f "${TMP}" "${TMP2}"
}

# Test normal files

# First test that each handle has 1 file pointer; a read after a write should
# not return the written data.
{
	rm -f "${TMP}"
	TMP=$(mktemp -t mapfile)

	mapfile file "${TMP}" "w+e"
	assert 0 $? "mapfile to standard file should pass"
	assert_not "" "${file}" "mapfile file should return handle"

	mapfile_write "${file}" "test 1 2 3"
	assert 0 $? "mapfile_write to standard file should pass"

	line=random
	mapfile_read "${file}" line
	assert 1 $? "mapfile_read from standard file after writing should EOF"
	assert "" "${line}" "mapfile_read should match (file pointer moving)"

	echo "blah" >> "${TMP}"
	mapfile_read "${file}" line
	assert 0 $? "mapfile_read from standard file after manual writing should pass"
	assert "blah" "${line}" "mapfile_read should match 2"

	mapfile_close "${file}"
}

{
	rm -f "${TMP}"
	TMP=$(mktemp -ut mapfile)
	assert_true mapfile file "${TMP}" "w+x"
	assert_not "" "${file}" "mapfile file should return handle"
	assert_true mapfile_write "${file}" "test 1 2 3"
	assert_true mapfile_close "${file}"

	assert_true mapfile file "${TMP}" "w+"
	assert_not "" "${file}" "mapfile file should return handle"
	assert_true mapfile_write "${file}" "test 3 2 1"
	assert_true mapfile_close "${file}"
	assert_file - "${TMP}" <<-EOF
	test 3 2 1
	EOF
}

{
	rm -f "${TMP}"
	TMP=$(mktemp -ut mapfile)
	assert_true mapfile file "${TMP}" "w+x"
	assert_not "" "${file}" "mapfile file should return handle"
	assert_true mapfile_write "${file}" "test 1 2 3"
	assert_true mapfile_close "${file}"

	assert_false expect_error_on_stderr mapfile file "${TMP}" "wx"

	assert_file - "${TMP}" <<-EOF
	test 1 2 3
	EOF
}

{
	rm -f "${TMP}"
	TMP=$(mktemp -ut mapfile)
	assert_true mapfile file "${TMP}" "w+x"
	assert_not "" "${file}" "mapfile file should return handle"
	assert_true mapfile_write "${file}" "test 1 2 3"
	assert_true mapfile_close "${file}"

	assert_false expect_error_on_stderr noclobber mapfile file "${TMP}" "w+"
}

# Now test read setting vars properly.
{
	rm -f "${TMP}"
	TMP=$(mktemp -t mapfile)
	mapfile file_out "${TMP}" "we"
	assert 0 $? "mapfile to standard file_out should pass"
	assert_not "" "${file_out}" "mapfile file_out should return handle"

	mapfile file_in "${TMP}" "re"
	assert 0 $? "mapfile to standard file_in should pass"
	assert_not "" "${file_in}" "mapfile file_in should return handle"

	mapfile_write "${file_out}" "test 1 2 3"
	assert 0 $? "mapfile_write to standard file_out should pass"

	mapfile_read "${file_in}" line
	assert 0 $? "mapfile_read from standard file_in to 1 var should pass"
	assert "test 1 2 3" "${line}" "mapfile_read should consume an entire line"

	mapfile_write "${file_out}" "test"
	assert 0 $? "mapfile_write to standard file_out should pass"
	mapfile_read "${file_in}" line
	assert 0 $? "mapfile_read from standard file_in to 1 var should pass"
	assert "test" "${line}" "mapfile_read should match line 1"

	# IFS= mode
	mapfile_write "${file_out}" " test   1 2 3 "
	assert 0 $? "mapfile_write to standard file_out should pass"
	extra="blah"
	IFS= mapfile_read "${file_in}" line extra
	assert 0 $? "mapfile_read from standard file_in to 2 var should pass"
	echo "line '${line}' extra '${extra}'"
	assert " test   1 2 3 " "${line}" "mapfile_read IFS= should match line 2"
	assert "" "${extra}" "mapfile_read IFS= should match extra 2"

	# IFS mode and default read -r behavior
	mapfile_write "${file_out}" " t\\est   1 2 3 "
	assert 0 $? "mapfile_write to standard file_out should pass"
	extra="blah"
	mapfile_read "${file_in}" line extra
	assert 0 $? "mapfile_read from standard file_in to 2.1 var should pass"
	assert "t\\est" "${line}" "mapfile_read should match line 2.1"
	assert "1 2 3" "${extra}" "mapfile_read should match extra 2.1"

	mapfile_write "${file_out}" "test 1 2 3"
	assert 0 $? "mapfile_write to standard file_out should pass"
	mapfile_read "${file_in}" line one two
	assert 0 $? "mapfile_read from standard file_in to 3 var should pass"
	assert "test" "${line}" "mapfile_read should match line 3"
	assert "1" "${one}" "mapfile_read should match one 3"
	assert "2 3" "${two}" "mapfile_read should match two 3"

	mapfile_write "${file_out}" "test 1 2 3"
	assert 0 $? "mapfile_write to standard file_out should pass"
	mapfile_read "${file_in}" line one two three
	assert 0 $? "mapfile_read from standard file_in to 4 var should pass"
	assert "test" "${line}" "mapfile_read should match line 4"
	assert "1" "${one}" "mapfile_read should match one 4"
	assert "2" "${two}" "mapfile_read should match two 4"
	assert "3" "${three}" "mapfile_read should match three 4"

	mapfile_write "${file_out}" "test 1a 2b 3c 4"
	assert 0 $? "mapfile_write to standard file_out should pass"
	nothing=nothing
	in=in
	here=here
	mapfile_read "${file_in}" line one two three nothing in here
	assert 0 $? "mapfile_read from standard file_in to 4+ var should pass"
	assert "test" "${line}" "mapfile_read should match line 4+"
	assert "1a" "${one}" "mapfile_read should match one 4+"
	assert "2b" "${two}" "mapfile_read should match two 4+"
	assert "3c" "${three}" "mapfile_read should match three 4+"
	assert "4" "${nothing}" "mapfile_read should clear nothing 4+"
	assert "" "${in}" "mapfile_read should clear in 4+"
	assert "NULL" "${in-NULL}" "mapfile_read should unset in 4+"
	assert "" "${here}" "mapfile_read should clear here 4+"
	assert "NULL" "${here-NULL}" "mapfile_read should unset here 4+"

	assert_ret 0 mapfile_close "${file_in}"
	assert_ret 0 mapfile_close "${file_out}"
	rm -f "${TMP}"
}
fi

# Test \ handling
{
	TMP=$(mktemp -t mapfile)

	expected='\blah\\b\\\\lah'
	echo "${expected}" >> "${TMP}"
	assert_ret 0 mapfile handle "${TMP}" "re"
	unset line
	assert_ret 0 mapfile_read "${handle}" line
	assert_ret 0 mapfile_close "${handle}"
	assert "${expected}" "${line}" "line with backslashes should match"
	rm -f "${TMP}"
}

# Should only return full lines as read(1) does
{
	rm -f "${TMP}"
	TMP=$(mktemp -t mapfile)
	mapfile file_in "${TMP}" "re"
	assert 0 $? "mapfile to standard file_in should pass"
	assert_not "" "${file_in}" "mapfile file_in should return handle"

	echo -n "blah" > "${TMP}"
	mapfile_read "${file_in}" output
	assert 1 "$?" "read without newline should return EOF"
	assert "blah" "${output}" "output should match"

	if mapfile_keeps_file_open_on_eof "${file_in}"; then
		echo "" >> "${TMP}"
		mapfile_read "${file_in}" output
		assert 0 "$?" "read after newline (without rewind) should return success"
		assert '' "${output}" "output should be empty"

		echo "foo" >> "${TMP}"
		mapfile_read "${file_in}" output
		assert 0 "$?" "read after newline (without rewind) should succeed"
		assert 'foo' "${output}" "output should match"
	fi
	assert_ret 0 mapfile_close "${file_in}"
}

# Test mapfile_read_loop
{
	rm -f "${TMP}"
	TMP=$(mktemp -t mapfile)

	jot 10 0 > "${TMP}"

	expectedfds=$(procstat -f $$|wc -l)
	procstat -f $$ >&2
	i=0
	while mapfile_read_loop "${TMP}" n; do
		assert "$i" "$n" "value should match 1 $i"
		echo "${n}"
		i=$((i + 1))
	done
	assert 10 "${i}"
	fds=$(procstat -f $$|wc -l)
	echo "-" >&2
	procstat -f $$ >&2
	[ ${JAILED} -eq 0 ] && assert "${expectedfds}" "${fds}" "fd leak 1"
}

# Test mapfile_read_loop_redir
{
	rm -f "${TMP}"
	TMP=$(mktemp -t mapfile)

	jot 10 0 > "${TMP}"

	expectedfds=$(procstat -f $$|wc -l)
	procstat -f $$ >&2
	i=0
	while mapfile_read_loop_redir n; do
		assert "$i" "$n" "value should match 1 $i"
		echo "${n}"
		i=$((i + 1))
	done < "${TMP}"
	assert 10 "${i}"
	fds=$(procstat -f $$|wc -l)
	[ ${JAILED} -eq 0 ] && assert "${expectedfds}" "${fds}" "fd leak 2"
}

# Test mapfile_read_loop_redir with nested call
{
	rm -f "${TMP}"
	TMP=$(mktemp -t mapfile)

	jot 10 0 > "${TMP}"
	echo inner > "${TMP}.2"

	expectedfds=$(procstat -f $$|wc -l)
	i=0
	while mapfile_read_loop_redir n; do
		assert "$i" "$n" "value should match 1 $i"
		echo "${n}"
		i=$((i + 1))
		mapfile_read_loop_redir n < "${TMP}.2"
		assert "inner" "$n" "nested call on stdin"
	done < "${TMP}"
	assert 10 "$i"
	rm -f "${TMP}" "${TMP}.2"
	fds=$(procstat -f $$|wc -l)
	[ ${JAILED} -eq 0 ] && assert "${expectedfds}" "${fds}" "fd leak 2"
}

{
	TDIR=$(mktemp -dt mapfile)
	i=0
	max=100
	{
		z=0
		until [ $z -eq $max ]; do
			echo "$z"
			z=$((z + 1))
		done
	} | while mapfile_read_loop_redir n; do
		assert "${i}" "${n}"
		echo "$((n + 1))"
		i=$((i + 1))
	done | while mapfile_read_loop_redir n; do
		assert "$((i + 1))" "${n}"
		echo "$((n + 1))"
		i=$((i + 1))
	done | while mapfile_read_loop_redir n; do
		assert "$((i + 2))" "${n}"
		echo "$((n + 1))"
		i=$((i + 1))
	done | while mapfile_read_loop_redir n; do
		assert "$((i + 3))" "${n}"
		echo "$((n + 1))"
		i=$((i + 1))
	done | while mapfile_read_loop_redir n; do
		assert "$((i + 4))" "${n}"
		echo "$((n + 1))"
		i=$((i + 1))
	done | while mapfile_read_loop_redir n; do
		assert "$((i + 5))" "${n}"
		touch "${TDIR:?}/${n}"
		i=$((i + 1))
	done
	assert_false expect_error_on_stderr rmdir "${TDIR:?}"
	n=5
	until [ $n -eq $((max + 5)) ]; do
		assert_true [ -e "${TDIR:?}/${n}" ]
		assert_true unlink "${TDIR:?}/${n}"
		n=$((n + 1))
	done
	assert_true rmdir "${TDIR:?}"
}

# Test mapfile_read_loop_redir with early return
{
	rm -f "${TMP}"
	TMP=$(mktemp -t mapfile)

	jot 10 0 > "${TMP}"

	expectedfds=$(procstat -f $$|wc -l)
	i=0
	while mapfile_read_loop_redir n; do
		assert "$i" "$n" "value should match 1 $i"
		echo "${n}"
		i=$((i + 1))
		if [ "${n}" -eq 5 ]; then
			break
		fi
	done < "${TMP}"
	assert 6 "${i}"
	# This may end up reading 6 next due to reused /dev/stdin
	i=0
	while mapfile_read_loop_redir n; do
		assert "$i" "$n" "value should match 1 $i"
		echo "${n}"
		i=$((i + 1))
	done < "${TMP}"
	assert 10 "$i"
	fds=$(procstat -f $$|wc -l)
	echo "-" >&2
	procstat -f $$ >&2
	[ ${JAILED} -eq 0 ] && assert "${expectedfds}" "${fds}" "fd leak 2"
}

# Crashed in mapfile_read_loop_close_stdin
{
	rm -f "${TMP}"
	TMP=$(mktemp -u)
	echo > "${TMP}"
	assert_true mapfile file_read "${TMP}" "re"
	while mapfile_read_loop_redir foo; do
		mapfile_read_loop_redir n < "${TMP}"
	done <<-EOF
	$(echo)
	EOF
	assert_true mapfile_close "${file_read}"
	rm -f "${TMP}"
}

# Test mapfile_read_loop_redir with multi vars in IFS= mode
{
	rm -f "${TMP}"
	TMP=$(mktemp -t mapfile)

	i=0
	until [ ${i} -eq 10 ]; do
		echo "   ${i}  $((i + 5)) "
		i=$((i + 1))
	done > "${TMP}"

	expectedfds=$(procstat -f $$|wc -l)
	procstat -f $$ >&2
	i=0
	while IFS= mapfile_read_loop_redir n y; do
		echo "'${n}' '${y}  '"
		assert "   $i  $((i + 5)) " "$n" "value should match 2 $i"
		assert '' "$y" 'value should match 2 for y - blank'
		i=$((i + 1))
	done < "${TMP}"
	fds=$(procstat -f $$|wc -l)
	assert 10 "${i}"
	echo "-" >&2
	procstat -f $$ >&2
	[ ${JAILED} -eq 0 ] && assert "${expectedfds}" "${fds}" "fd leak 3"
}

# Test mapfile_read_loop_redir with multi vars in IFS mode
{
	rm -f "${TMP}"
	TMP=$(mktemp -t mapfile)

	i=0
	until [ ${i} -eq 10 ]; do
		echo "   ${i}  $((i + 5)) "
		i=$((i + 1))
	done > "${TMP}"

	expectedfds=$(procstat -f $$|wc -l)
	procstat -f $$ >&2
	i=0
	while mapfile_read_loop_redir n y; do
		echo "'${n}' '${y}'"
		assert "$i" "$n" "value should match 3 $i"
		assert "$((i + 5))" "$y" "value should match 3 $((i + 5))"
		i=$((i + 1))
	done < "${TMP}"
	assert 10 "$i"
	fds=$(procstat -f $$|wc -l)
	echo "-" >&2
	procstat -f $$ >&2
	[ ${JAILED} -eq 0 ] && assert "${expectedfds}" "${fds}" "fd leak 4"
}

# Piped mapfile_read_loop_redir
{
	rm -f "${TMP}"
	TMP=$(mktemp -t mapfile)

	i=0
	until [ ${i} -eq 10 ]; do
		echo "   ${i}  $((i + 5)) "
		i=$((i + 1))
	done > "${TMP}"

	expectedfds=$(procstat -f $$|wc -l)
	procstat -f $$ >&2
	i=0
	while mapfile_read_loop_redir n y; do
		echo "'${n}' '${y}'"
	done < "${TMP}" | while mapfile_read_loop_redir n y; do
		echo "'${n}' '${y}'"
		assert "'$i'" "$n" "value should match quoted 4 $i"
		assert "'$((i + 5))'" "$y" "value should match quoted 4 $((i + 5))"
		i=$((i + 1))
	done
	fds=$(procstat -f $$|wc -l)
	echo "-" >&2
	procstat -f $$ >&2
	[ ${JAILED} -eq 0 ] && assert "${expectedfds}" "${fds}" "fd leak 5"
}

# Piped mapfile_read_loop_redir
{
	rm -f "${TMP}"
	TMP=$(mktemp -t mapfile)

	i=0
	until [ ${i} -eq 10 ]; do
		echo "   ${i}  $((i + 5)) "
		i=$((i + 1))
	done > "${TMP}"

	expectedfds=$(procstat -f $$|wc -l)
	procstat -f $$ >&2
	i=0
	cat "${TMP}" | while mapfile_read_loop_redir n y; do
		echo "'${n}' '${y}'"
	done | while mapfile_read_loop_redir n y; do
		echo "'${n}' '${y}'"
		assert "'$i'" "$n" "value should match quoted 5 $i"
		assert "'$((i + 5))'" "$y" "value should match quoted 5 $((i + 5))"
		i=$((i + 1))
	done
	fds=$(procstat -f $$|wc -l)
	echo "-" >&2
	procstat -f $$ >&2
	[ ${JAILED} -eq 0 ] && assert "${expectedfds}" "${fds}" "fd leak 6"
}

# Nested mapfile_read_loop_redir
# It's possible that a nested one will try to read from a parent's handle.
{
	rm -f "${TMP}"
	TDIR=$(mktemp -dt mapfile)
	TMP=$(mktemp -t mapfile)

	i=0
	until [ ${i} -eq 10 ]; do
		echo "   ${i}  $((i + 5)) "
		i=$((i + 1))
	done > "${TMP}"

	expectedfds=$(procstat -f $$|wc -l)
	procstat -f $$ >&2
	i=0
	while mapfile_read_loop_redir n y; do
		echo "OUTER 1: n=$n y=$y" >&2
		echo "'${n}' '${y}'" | while mapfile_read_loop_redir m z; do
			echo "INNER 1: m=$m z=$z" >&2
			echo "'${m}' '${z}'"
		done
	done < "${TMP}" | while mapfile_read_loop_redir n y; do
		echo "INNER 2: n=$n y=$y" >&2
		assert "''$i''" "$n" "value should match double quoted 6 $i"
		assert "''$((i + 5))''" "$y" "value should match double quoted 6 $((i + 5))"
		touch "${TDIR:?}/${i}"
		i=$((i + 1))
	done
	i=0
	until [ ${i} -eq 10 ]; do
		[ -e "${TDIR:?}/${i}" ]
		assert 0 $? "inner loop did not run i=$i; found: $(/bin/ls ${TDIR})"
		i=$((i + 1))
	done
	fds=$(procstat -f $$|wc -l)
	echo "-" >&2
	procstat -f $$ >&2
	[ ${JAILED} -eq 0 ] && assert "${expectedfds}" "${fds}" "fd leak 7"
	rm -rf "${TDIR}"
	rm -f "${TMP}"
}

{
	TMP=$(mktemp -t mapfile)
	TMP2=$(mktemp -t mapfile)

	:>"${TMP}"
	assert_ret 0 mapfile handle "${TMP2}" "we"
	cat "${TMP}" | mapfile_write "${handle}"
	assert 0 "$?" "pipe exit status"
	assert_ret 0 mapfile_close "${handle}"
	[ ! -s "${TMP2}" ]
	assert 0 "$?" "'cat <empty file> | mapfile_write' should not write anything --"$'\n'"$(cat -vet "${TMP2}")"
	rm -f "${TMP}" "${TMP2}"
}

{
	TMP=$(mktemp -t mapfile)
	TMP2=$(mktemp -t mapfile)

	:>"${TMP}"
	assert_ret 0 mapfile handle "${TMP2}" "we"
	mapfile_write "${handle}" -n "blah"
	assert 0 "$?" "pipe exit status"
	assert_ret 0 mapfile_close "${handle}"
	assert "blah" "$(cat -vet "${TMP2}")"
	assert_ret 0 [ -s "${TMP2}" ]
	rm -f "${TMP}" "${TMP2}"
}


{
	TMP=$(mktemp -t mapfile)
	TMP2=$(mktemp -t mapfile)

	:>"${TMP}"
	assert_ret 0 mapfile handle "${TMP2}" "we"
	echo blah | mapfile_write "${handle}" -n
	assert 0 "$?" "pipe exit status"
	assert_ret 0 mapfile_close "${handle}"
	assert "blah" "$(cat -vet "${TMP2}")"
	assert_ret 0 [ -s "${TMP2}" ]
	rm -f "${TMP}" "${TMP2}"
}

{
	assert_ret_not 0 expect_error_on_stderr mapfile_cat_file /nonexistent
	assert_ret_not 0 mapfile_cat_file -q /nonexistent
}

{
	TMP=$(mktemp -t mapfile)
	TMP2=$(mktemp -t mapfile)

	:>"${TMP}"
	assert_ret 0 mapfile handle "${TMP2}" "we"
	assert_ret 0 mapfile_cat_file "${TMP}" |
	    assert_ret 0 mapfile_write "${handle}"
	assert 0 "$?" "pipe exit status"
	assert 0 "${_mapfile_cat_file_lines_read}"
	assert_ret 0 mapfile_close "${handle}"
	[ ! -s "${TMP2}" ]
	assert 0 "$?" "'mapfile_cat_file <empty file> | mapfile_write' should not write anything"
	rm -f "${TMP}" "${TMP2}"
}

{
	TMP=$(mktemp -t mapfile)
	assert_ret 0 mapfile_cat_file - > "${TMP}" <<-EOF
	1
	2
	EOF
	assert 2 "${_mapfile_cat_file_lines_read}"
	assert_file - "${TMP}" <<-EOF
	1
	2
	EOF
	rm -f "${TMP}"
}

{
	TMP=$(mktemp -t mapfile)
	assert_ret 0 mapfile_cat_file > "${TMP}" <<-EOF
	1
	2
	EOF
	assert 2 "${_mapfile_cat_file_lines_read}"
	assert_file - "${TMP}" <<-EOF
	1
	2
	EOF
	rm -f "${TMP}"
}

{
	TMP=$(mktemp -t mapfile)
	TMP2=$(mktemp -t mapfile)

	generate_data > "${TMP}"

	:>"${TMP2}"
	assert_ret 0 mapfile handle "${TMP2}" "we"
	assert_ret 0 mapfile_cat_file "${TMP}" |
	    assert_ret 0 mapfile_write "${handle}"
	assert 0 "$?" "pipe exit status"
	assert_ret 0 mapfile_close "${handle}"
	assert_ret 0 diff -u "${TMP}" "${TMP2}"

	rm -f "${TMP2}"
	:>"${TMP2}"
	assert_ret 0 mapfile handle "${TMP2}" "we"
	assert_ret 0 mapfile_write "${handle}" <<-EOF
	$(cat "${TMP}")
	EOF
	assert_ret 0 mapfile_close "${handle}"
	assert_ret 0 diff -u "${TMP}" "${TMP2}"

	rm -f "${TMP}" "${TMP2}"
}

{
	TMP=$(mktemp -t mapfile)
	TMP2=$(mktemp -t mapfile)

	generate_data > "${TMP}"

	:>"${TMP2}"
	assert_ret 0 mapfile read_handle "${TMP}" "re"
	assert_ret 0 mapfile_cat "${read_handle}" > "${TMP2}"
	assert_ret 0 mapfile_close "${read_handle}"
	assert_ret 0 diff -u "${TMP}" "${TMP2}"
	rm -f "${TMP}" "${TMP2}"
}

{
	TMP=$(mktemp -t mapfile)
	TMP2=$(mktemp -t mapfile)

	generate_data > "${TMP}"

	:>"${TMP2}"
	assert_ret 0 mapfile_cat_file "${TMP}" > "${TMP2}"
	count_lines "${TMP}" lines
	assert "${lines}" "${_mapfile_cat_file_lines_read}"
	assert_ret 0 diff -u "${TMP}" "${TMP2}"
	rm -f "${TMP}" "${TMP2}"
}

{
	TMP=$(mktemp -t mapfile)
	TMP2=$(mktemp -t mapfile)

	generate_data > "${TMP}"

	:>"${TMP2}"
	assert_ret 0 mapfile read_handle "${TMP}" "re"
	assert_ret 0 mapfile_cat "${read_handle}" | (
		assert_ret 0 mapfile handle "${TMP2}" "we"
		assert_ret 0 mapfile_write "${handle}"
		assert_ret 0 mapfile_close "${handle}"
	)
	assert 0 "$?" "pipe exit status"
	assert_ret 0 mapfile_close "${read_handle}"
	assert_ret 0 diff -u "${TMP}" "${TMP2}"

	rm -f "${TMP2}"
	:>"${TMP2}"
	assert_ret 0 mapfile handle "${TMP2}" "we"
	assert_ret 0 mapfile_write "${handle}" <<-EOF
	$(cat "${TMP}")
	EOF
	assert_ret 0 mapfile_close "${handle}"
	assert_ret 0 diff -u "${TMP}" "${TMP2}"

	rm -f "${TMP}" "${TMP2}"
}

{
	TMP=$(mktemp -t mapfile)
	TMP2=$(mktemp -t mapfile)

	generate_data > "${TMP}"

	:>"${TMP2}"
	assert_ret 0 mapfile handle "${TMP2}" "we"
	cat "${TMP}" | mapfile_write "${handle}"
	assert 0 "$?" "pipe exit status"
	assert_ret 0 mapfile_close "${handle}"
	assert_ret 0 diff -u "${TMP}" "${TMP2}"

	rm -f "${TMP2}"
	:>"${TMP2}"
	assert_ret 0 mapfile handle "${TMP2}" "we"
	assert_ret 0 mapfile_write "${handle}" <<-EOF
	$(cat "${TMP}")
	EOF
	assert_ret 0 mapfile_close "${handle}"
	assert_ret 0 diff -u "${TMP}" "${TMP2}"

	rm -f "${TMP}" "${TMP2}"
}

# Test newline write handling
{
	rm -f "${TMP}"
	TMP=$(mktemp -t mapfile)
	assert_ret 0 mapfile file_out "${TMP}" "we"
	assert_ret 0 mapfile_write "${file_out}" ""
	assert_ret 0 mapfile_close "${file_out}"
	size=$(stat -f %z "${TMP}")
	assert "0" "$?"
	assert "1" "${size}"
	assert '$' "$(cat -vet "${TMP}")"
	value="$(mapfile_cat_file "${TMP}")"
	assert "empty" "${value:-empty}"
	assert_ret 0 mapfile_cat_file "${TMP}" | (
		lines=0
		while read -r line; do
			assert "empty" "${line:-empty}"
			lines=$((lines + 1))
		done
		assert 1 "${lines}"
	)
	assert 0 "$?"
	assert_ret 0 mapfile file_in "${TMP}" "re"
	lines=0
	while mapfile_read "${file_in}" line; do
		assert "empty" "${line:-empty}"
		lines=$((lines + 1))
	done
	assert 1 "${lines}"
	assert_ret 0 mapfile_close "${file_in}"
	lines=0
	while mapfile_read_loop "${TMP}" line; do
		assert "empty" "${line:-empty}"
		lines=$((lines + 1))
	done
	assert 1 "${lines}"
}

# Test newline write handling in pipe
{
	rm -f "${TMP}"
	TMP=$(mktemp -t mapfile)
	assert_ret 0 mapfile file_out "${TMP}" "we"
	echo | assert_ret 0 mapfile_write "${file_out}"
	assert 0 "$?"
	assert_ret 0 mapfile_close "${file_out}"
	size=$(stat -f %z "${TMP}")
	assert "0" "$?"
	assert "1" "${size}"
	assert '$' "$(cat -vet "${TMP}")"
	value="$(mapfile_cat_file "${TMP}")"
	assert "empty" "${value:-empty}"
	assert_ret 0 mapfile_cat_file "${TMP}" | (
		lines=0
		while read -r line; do
			assert "empty" "${line:-empty}"
			lines=$((lines + 1))
		done
		assert 1 "${lines}"
	)
	assert 0 "$?"
	assert_ret 0 mapfile file_in "${TMP}" "re"
	lines=0
	while mapfile_read "${file_in}" line; do
		assert "empty" "${line:-empty}"
		lines=$((lines + 1))
	done
	assert 1 "${lines}"
	assert_ret 0 mapfile_close "${file_in}"
	lines=0
	while mapfile_read_loop "${TMP}" line; do
		assert "empty" "${line:-empty}"
		lines=$((lines + 1))
	done
	assert 1 "${lines}"
}

# Test blank write handling
{
	rm -f "${TMP}"
	TMP=$(mktemp -t mapfile)
	assert_ret 0 mapfile file_out "${TMP}" "we"
	assert_ret 0 mapfile_write "${file_out}" -n ""
	assert_ret 0 mapfile_close "${file_out}"
	size=$(stat -f %z "${TMP}")
	assert "0" "$?"
	assert "0" "${size}"
	assert '' "$(cat -vet "${TMP}")"
	value="$(mapfile_cat_file "${TMP}")"
	assert "empty" "${value:-empty}"
	assert_ret 0 mapfile_cat_file "${TMP}" | (
		lines=0
		while read -r line; do
			assert "empty" "${line:-empty}"
			lines=$((lines + 1))
		done
		assert 0 "${lines}"
	)
	assert 0 "$?"
	assert_ret 0 mapfile file_in "${TMP}" "re"
	lines=0
	while mapfile_read "${file_in}" line; do
		assert "empty" "${line:-empty}"
		lines=$((lines + 1))
	done
	assert 0 "${lines}"
	assert_ret 0 mapfile_close "${file_in}"
	lines=0
	while mapfile_read_loop "${TMP}" line; do
		assert "empty" "${line:-empty}"
		lines=$((lines + 1))
	done
	assert 0 "${lines}"
}

# Test blank write handling in pipe
{
	rm -f "${TMP}"
	TMP=$(mktemp -t mapfile)
	assert_ret 0 mapfile file_out "${TMP}" "we"
	: | assert_ret 0 mapfile_write "${file_out}" -n ""
	assert 0 "$?"
	assert_ret 0 mapfile_close "${file_out}"
	size=$(stat -f %z "${TMP}")
	assert "0" "$?"
	assert "0" "${size}"
	assert '' "$(cat -vet "${TMP}")"
	value="$(mapfile_cat_file "${TMP}")"
	assert "empty" "${value:-empty}"
	assert_ret 0 mapfile_cat_file "${TMP}" | (
		lines=0
		while read -r line; do
			assert "empty" "${line:-empty}"
			lines=$((lines + 1))
		done
		assert 0 "${lines}"
	)
	assert 0 "$?"
	assert_ret 0 mapfile file_in "${TMP}" "re"
	lines=0
	while mapfile_read "${file_in}" line; do
		assert "empty" "${line:-empty}"
		lines=$((lines + 1))
	done
	assert 0 "${lines}"
	assert_ret 0 mapfile_close "${file_in}"
	lines=0
	while mapfile_read_loop "${TMP}" line; do
		assert "empty" "${line:-empty}"
		lines=$((lines + 1))
	done
	assert 0 "${lines}"
	rm -f "${TMP}"
}

{
	rm -f "${TMP}"
	TMP=$(mktemp -ut mapfile)
	assert_true mapfile file_out "${TMP}" "we"
	assert_true mapfile_write "${file_out}" -- "-n blah"
	assert_true mapfile_close "${file_out}"
	assert_file - "${TMP}" <<-EOF
	-n blah
	EOF
}

{
	rm -f "${TMP}"
	TMP=$(mktemp -ut mapfile)
	assert_true mapfile file_out "${TMP}" "we"
	echo "-n blah" | assert_true mapfile_write "${file_out}"
	assert 0 "$?"
	assert_true mapfile_close "${file_out}"
	assert_file - "${TMP}" <<-EOF
	-n blah
	EOF
}

# mapfile_read_proc hackery
{
	rm -f "${TMP}"
	TMP=$(mktemp -ut mapfile)
	generate_data > "${TMP}"
	assert_ret 0 mapfile_read_proc ps_handle cat "${TMP}"
	assert_not "" "${ps_handle}"
	#assert_ret 0 kill -0 "$!"
	assert_ret 0 mapfile_cat "${ps_handle}" > "${TMP}.2"
	count_lines "${TMP}" lines
	assert "${lines}" "${_mapfile_cat_lines_read}"
	assert_file "${TMP}" "${TMP}.2"
	assert_ret 0 mapfile_close "${ps_handle}"
	#assert_ret_not 0 kill -0 "$!"
}

{
	TMP="$(mktemp)"
	cat > "${TMP}" <<-EOF
	1 2
	3 4
	5
	6 7 8
	EOF
	assert_true mapfile f_out /dev/stdout "w"
	while mapfile_read_loop "${TMP}" a b; do
		assert_true mapfile_write "${f_out}" "a=${a} b=${b}"
	done > "${TMP}.2"
	assert_true mapfile_close "${f_out}"
	assert_file - "${TMP}.2" <<-EOF
	a=1 b=2
	a=3 b=4
	a=5 b=
	a=6 b=7 8
	EOF
	rm -f "${TMP}" "${TMP}.2"
	assert_true hash_assert_no_vars "file*"
	assert_true hash_assert_no_vars "it*"
	assert_true hash_assert_no_vars "mapfile*"
}

# Check for no EOL newline reads.
{
	TMP="$(mktemp)"
	echo -n "1234" > "${TMP}"
	{
		assert_true mapfile_cat_file "${TMP}"
		echo
	} > "${TMP}.2"
	assert_file - "${TMP}.2" <<-EOF
	1234
	EOF
	rm -f "${TMP}"
}

{
	TMP="$(mktemp)"
	echo -n "1234" > "${TMP}"
	assert_true mapfile handle "${TMP}" "re"
	unset data
	assert_ret 1 mapfile_read "${handle}" data
	assert_true mapfile_close "${handle}"
	assert "1234" "${data}"
	rm -f "${TMP}"
}

{
	TMP="$(mktemp -u)"
	assert_true mapfile whandle "${TMP}" "we"
	echo -n "1234" | mapfile_write "${whandle}" -n
	assert_true mapfile_close "${whandle}"
	assert "1234" "$(cat -ve "${TMP}")"
	unset data
	assert_ret 1 read data < "${TMP}"
	assert "1234" "${data}"
	rm -f "${TMP}"
}

# Same but without mapfile_write -n flag
{
	TMP="$(mktemp -u)"
	assert_true mapfile whandle "${TMP}" "we"
	echo -n "1234" | mapfile_write "${whandle}"
	assert_true mapfile_close "${whandle}"
	assert "1234\$" "$(cat -ve "${TMP}")"
	unset data
	assert_ret 0 read data < "${TMP}"
	assert "1234" "${data}"
	rm -f "${TMP}"
}

exit 0
