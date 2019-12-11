#! /bin/sh

set -e
. common.sh
. ${SCRIPTPREFIX}/include/hash.sh
. ${SCRIPTPREFIX}/include/parallel.sh
. ${SCRIPTPREFIX}/include/util.sh
set +e

JAILED=$(sysctl -n security.jail.jailed 2>/dev/null || echo 0)

LINES=20

cleanup() {
	kill_jobs
	if [ -n "${TMP}" ]; then
		rm -rf "${TMP}"
		unset TMP
	fi
	if [ -n "${TMP2}" ]; then
		rm -rf "${TMP2}"
		unset TMP2
	fi
}
trap cleanup EXIT

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
		pipe) echo "${n}" ;;
		mapfile) mapfile_write "${out}" "${n}" ;;
		esac
		n=$((n + 1))
	done
	if [ "${type}" = "mapfile" ]; then
		mapfile_close "${out}"
	fi
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
		assert "$n" "$line" "mapfile_read handle1 should match line $n"

		mapfile_read "${handle2}" line
		assert 0 $? "mapfile_read handle2 should succeed line $n"
		assert "$n" "$line" "mapfile_read handle2 should match line $n"

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

	kill_jobs
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

	# IFS mode
	mapfile_write "${file_out}" " test   1 2 3 "
	assert 0 $? "mapfile_write to standard file_out should pass"
	extra="blah"
	mapfile_read "${file_in}" line extra
	assert 0 $? "mapfile_read from standard file_in to 2.1 var should pass"
	assert "test" "${line}" "mapfile_read should match line 2.1"
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
	assert "" "${here}" "mapfile_read should clear here 4+"
}
fi

# Test mapfile_read_loop
{
	rm -f "${TMP}"
	TMP=$(mktemp -t mapfile)

	jot 10 0 > "${TMP}"

	# For some reason Jenkins is leaking in fd 8
	exec 8>&- || :
	expectedfds=$(procstat -f $$|wc -l)
	procstat -f $$ >&2
	i=0
	while mapfile_read_loop "${TMP}" n; do
		assert "$i" "$n" "value should match 1 $i"
		echo "${n}"
		i=$((i + 1))
	done
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
	i=0
	while mapfile_read_loop_redir n; do
		assert "$i" "$n" "value should match 1 $i"
		echo "${n}"
		i=$((i + 1))
	done < "${TMP}"
	fds=$(procstat -f $$|wc -l)
	[ ${JAILED} -eq 0 ] && assert "${expectedfds}" "${fds}" "fd leak 2"
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
	i=0
	while IFS= mapfile_read_loop_redir n y; do
		echo "'${n}' '${y}  '"
		assert "   $i  $((i + 5)) " "$n" "value should match 2 $i"
		assert '' "$y" 'value should match 2 for y - blank'
		i=$((i + 1))
	done < "${TMP}"
	fds=$(procstat -f $$|wc -l)
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
	i=0
	while mapfile_read_loop_redir n y; do
		echo "'${n}' '${y}'"
		assert "$i" "$n" "value should match 3 $i"
		assert "$((i + 5))" "$y" "value should match 3 $((i + 5))"
		i=$((i + 1))
	done < "${TMP}"
	fds=$(procstat -f $$|wc -l)
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
		touch "${TDIR}/${i}"
		i=$((i + 1))
	done
	i=0
	until [ ${i} -eq 10 ]; do
		[ -e "${TDIR}/${i}" ]
		assert 0 $? "inner loop did not run i=$i; found: $(/bin/ls ${TDIR}):"
		i=$((i + 1))
	done
	fds=$(procstat -f $$|wc -l)
	[ ${JAILED} -eq 0 ] && assert "${expectedfds}" "${fds}" "fd leak 7"
	rm -rf "${TDIR}"
}
exit 0
