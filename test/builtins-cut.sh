. common.sh

case "$(type cut)" in
*"is a shell builtin") ;;
*) exit 77 ;;
esac

{
	val=$(echo foo/bar | cut -d / -f 2)
	assert "bar" "${val}"

	val=$(echo bar/foo | cut -d / -f 2)
	assert "foo" "${val}"
}

{
	TMPFILE="$(mktemp -ut cut)"

	echo foo/bar > "${TMPFILE}"
	val="$(cut -d / -f 2 < "${TMPFILE}")"
	assert "bar" "${val}"

	echo bar/foo > "${TMPFILE}"
	val="$(cut -d / -f 2 < "${TMPFILE}")"
	assert "foo" "${val}"

	rm -f "${TMPFILE}"
}
