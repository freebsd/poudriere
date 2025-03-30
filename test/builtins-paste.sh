. ./common.sh

case "$(type paste)" in
*"is a shell builtin") ;;
*) exit 77 ;;
esac

{
	TMPFILE=$(mktemp -ut paste)
	assert_true seq 1 10 > "${TMPFILE}"

	paste -s -d "A" - < "${TMPFILE}" > "${TMPFILE}.out"
	assert_file - "${TMPFILE}.out" <<-EOF
	1A2A3A4A5A6A7A8A9A10
	EOF

	paste -s - < "${TMPFILE}" > "${TMPFILE}.out"
	assert_file - "${TMPFILE}.out" <<-EOF
	1	2	3	4	5	6	7	8	9	10
	EOF

	paste -s -d "B" - < "${TMPFILE}" > "${TMPFILE}.out"
	assert_file - "${TMPFILE}.out" <<-EOF
	1B2B3B4B5B6B7B8B9B10
	EOF

	rm -f "${TMPFILE}" "${TMPFILE}.out"
}
