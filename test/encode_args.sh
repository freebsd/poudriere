set -e
. ./common.sh
set +e

encode_args data "1"
assert "1" "${data}" "encode 1 argument"
one=bad
decode_args_vars "${data}" one
assert 0 "$?" "decode_args_vars"
assert "1" "$one" "decode 2 argument argument 1"

encode_args data "'1'"
assert "'1'" "${data}" "encode 1 argument single-quoted"

encode_args data '"1"'
assert '"1"' "${data}" "encode 1 argument double-quoted"

# Test trailing spaces
encode_args data "'1' "
assert "'1' " "${data}" "encode 1 argument single-quoted trailing space"

encode_args data "'1'  "
assert "'1'  " "${data}" "encode 1 argument single-quoted 2 trailing spaces"

encode_args data "'1'   "
assert "'1'   " "${data}" "encode 1 argument single-quoted 3 trailing spaces"
assert 6 ${#data} "encode 1 argument single-quoted 3 trailing spaces length"

encode_args data "'1'  2"
assert "'1'  2" "${data}" "encode 1 argument single-quoted 2 trailing spaces data"

encode_args data '"1" '
assert '"1" ' "${data}" "encode 1 argument double-quoted trailing space"

encode_args data "'1'" ""
assert "'1'${ENCODE_SEP}${ENCODE_SEP}" "${data}" "encode 1 argument single-quoted trailing arg"

encode_args data "'1'" "" ""
assert "'1'${ENCODE_SEP}${ENCODE_SEP}${ENCODE_SEP}" "${data}" "encode 1 argument single-quoted 2 trailing arg"

encode_args data "'1'" "" "" "5"
assert "'1'${ENCODE_SEP}${ENCODE_SEP}${ENCODE_SEP}5" "${data}" "encode 1 argument single-quoted 2 trailing arg data"

encode_args data '"1"' ""
assert '"1"'"${ENCODE_SEP}${ENCODE_SEP}" "${data}" "encode 1 argument double-quoted trailing arg"

# Test embedded spaces
encode_args data "1" "2 3"
assert "1${ENCODE_SEP}2 3" "${data}" "encode 2 argument"
set -- bad bad bad bad bad
oldIFS="${IFS}"; IFS="${ENCODE_SEP}"; set -- ${data}; IFS="${oldIFS}"; unset oldIFS
assert 2 $# "decode 2 argument argcnt"
assert "1" "$1" "decode 2 argument argument 1"
assert "2 3" "$2" "decode 2 argument argument 2"
set -- bad bad bad bad bad
eval "$(decode_args data)"
assert 2 $# "decode 2 argument argcnt"
assert "1" "$1" "decode 2 argument argument 1"
assert "2 3" "$2" "decode 2 argument argument 2"
one=bad
two=bad
decode_args_vars "${data}" one two
assert 0 "$?" "decode_args_vars"
assert "1" "$one" "decode 2 argument argument 1"
assert "2 3" "$two" "decode 2 argument argument 2"

# Test embedded cmdsubst
TMP=$(mktemp -ut encoded_args)
encode_args data "\$(touch ${TMP})"
assert "\$(touch ${TMP})" "${data}" "encoded cmdsubst"
set -- bad bad bad bad bad
oldIFS="${IFS}"; IFS="${ENCODE_SEP}"; set -- ${data}; IFS="${oldIFS}"; unset oldIFS
[ -f "${TMP}" ]
assert 1 $? "decoding cmdsubst should not fire: ${TMP}"
set -- bad bad bad bad bad
eval "$(decode_args data)"
[ -f "${TMP}" ]
assert 1 $? "decoding cmdsubst should not fire: ${TMP}"

# Test 1 leading empty arguments
encode_args data "" "1"
assert "${ENCODE_SEP}1" "${data}" "encode 1 trailing args"
set -- bad bad bad bad bad
oldIFS="${IFS}"; IFS="${ENCODE_SEP}"; set -- ${data}; IFS="${oldIFS}"; unset oldIFS
assert 2 $# "decode 1 trailing arguments argcnt"
assert "" "$1" "decode 1 trailing arguments argument 1"
assert "1" "$2" "decode 1 trailing arguments argument 2"
set -- bad bad bad bad bad
eval "$(decode_args data)"
assert 2 $# "decode 1 trailing arguments argcnt"
assert "" "$1" "decode 1 trailing arguments argument 1"
assert "1" "$2" "decode 1 trailing arguments argument 2"

# Test 1 trailing empty arguments
encode_args data "1" ""
assert "1${ENCODE_SEP}${ENCODE_SEP}" "${data}" "encode 1 trailing args"
set -- bad bad bad bad bad
oldIFS="${IFS}"; IFS="${ENCODE_SEP}"; set -- ${data}; IFS="${oldIFS}"; unset oldIFS
assert 2 $# "decode 1 trailing arguments argcnt"
assert "1" "$1" "decode 1 trailing arguments argument 1"
assert "" "$2" "decode 1 trailing arguments argument 2"
set -- bad bad bad bad bad
eval "$(decode_args data)"
assert 2 $# "decode 1 trailing arguments argcnt"
assert "1" "$1" "decode 1 trailing arguments argument 1"
assert "" "$2" "decode 1 trailing arguments argument 2"

# Test leading, middle, and end empty arguments
encode_args data "" "" "1" ""
assert "${ENCODE_SEP}${ENCODE_SEP}1${ENCODE_SEP}${ENCODE_SEP}" "${data}" "encode 3 trailing args"
set -- bad bad bad bad bad
oldIFS="${IFS}"; IFS="${ENCODE_SEP}"; set -- ${data}; IFS="${oldIFS}"; unset oldIFS
assert 4 $# "decode 3 trailing arguments argcnt"
assert "" "$1" "decode 3 trailing arguments argument 1"
assert "" "$2" "decode 3 trailing arguments argument 2"
assert "1" "$3" "decode 3 trailing arguments argument 3"
assert "" "$4" "decode 3 trailing arguments argument 4"
set -- bad bad bad bad bad
eval "$(decode_args data)"
assert 4 $# "decode 3 trailing arguments argcnt"
assert "" "$1" "decode 3 trailing arguments argument 1"
assert "" "$2" "decode 3 trailing arguments argument 2"
assert "1" "$3" "decode 3 trailing arguments argument 3"
assert "" "$4" "decode 3 trailing arguments argument 4"
one=bad
two=bad
three=bad
four=bad
decode_args_vars "${data}" one two three four
assert 0 "$?" "decode_args_vars"
assert "" "$one" "decode 2 argument argument 1"
assert "" "$two" "decode 2 argument argument 2"
assert "1" "$three" "decode 2 argument argument 3"
assert "" "$four" "decode 2 argument argument 4"

# Test trailing empty arguments
encode_args data "1" "" "" ""
assert "1${ENCODE_SEP}${ENCODE_SEP}${ENCODE_SEP}${ENCODE_SEP}" "${data}" "encode 3 trailing args"
set -- bad bad bad bad bad
oldIFS="${IFS}"; IFS="${ENCODE_SEP}"; set -- ${data}; IFS="${oldIFS}"; unset oldIFS
assert 4 $# "decode 3 trailing arguments argcnt"
assert "1" "$1" "decode 3 trailing arguments argument 1"
assert "" "$2" "decode 3 trailing arguments argument 2"
assert "" "$3" "decode 3 trailing arguments argument 3"
assert "" "$4" "decode 3 trailing arguments argument 4"
set -- bad bad bad bad bad
eval "$(decode_args data)"
assert 4 $# "decode 3 trailing arguments argcnt"
assert "1" "$1" "decode 3 trailing arguments argument 1"
assert "" "$2" "decode 3 trailing arguments argument 2"
assert "" "$3" "decode 3 trailing arguments argument 3"
assert "" "$4" "decode 3 trailing arguments argument 4"
one=bad
two=bad
three=bad
four=bad
decode_args_vars "${data}" one two three four
assert 0 "$?" "decode_args_vars"
assert "1" "$one" "decode 2 argument argument 1"
assert "" "$two" "decode 2 argument argument 2"
assert "" "$three" "decode 2 argument argument 3"
assert "" "$four" "decode 2 argument argument 4"

# Test trailing empty arguments with data
encode_args data "1" "" "" "x"
assert "1${ENCODE_SEP}${ENCODE_SEP}${ENCODE_SEP}x" "${data}" "encode 3 trailing args x"
set -- bad bad bad bad bad
oldIFS="${IFS}"; IFS="${ENCODE_SEP}"; set -- ${data}; IFS="${oldIFS}"; unset oldIFS
assert 4 $# "decode 3 trailing arguments x argcnt"
assert "1" "$1" "decode 3 trailing arguments x argument 1"
assert "" "$2" "decode 3 trailing arguments x argument 2"
assert "" "$3" "decode 3 trailing arguments x argument 3"
assert "x" "$4" "decode 3 trailing arguments x argument 4"
set -- bad bad bad bad bad
_decode_args _decode_args data
eval "${_decode_args}"
assert 4 $# "decode 3 trailing arguments x argcnt"
assert "1" "$1" "decode 3 trailing arguments x argument 1"
assert "" "$2" "decode 3 trailing arguments x argument 2"
assert "" "$3" "decode 3 trailing arguments x argument 3"
assert "x" "$4" "decode 3 trailing arguments x argument 4"
one=bad
two=bad
three=bad
four=bad
decode_args_vars "${data}" one two three four
assert 0 "$?" "decode_args_vars"
assert "1" "$one" "decode 3 trailing arguments x argument 1"
assert "" "$two" "decode 3 trailing arguments x argument 2"
assert "" "$three" "decode 3 trailing arguments x argument 3"
assert "x" "$four" "decode 3 trailing arguments x argument 4"

encode_args data "1" "*" " * " " 4"
set -- bad bad bad bad bad
eval "$(decode_args data)"
assert 4 $# "decode 3 trailing arguments x argcnt"
assert "1" "$1" "decode 3 trailing arguments x argument 1"
assert "*" "$2" "decode 3 trailing arguments x argument 2"
assert " * " "$3" "decode 3 trailing arguments x argument 3"
assert " 4" "$4" "decode 3 trailing arguments x argument 4"
one=bad
two=bad
three=bad
four=bad
decode_args_vars "${data}" one two three four
assert 0 "$?" "decode_args_vars"
assert "1" "$one" "decode 3 trailing arguments x argument 1"
assert "*" "$two" "decode 3 trailing arguments x argument 2"
assert " * " "$three" "decode 3 trailing arguments x argument 3"
assert " 4" "$four" "decode 3 trailing arguments x argument 4"

decode_args_vars "${data}" one two
assert 0 "$?" "decode_args_vars"
assert "1" "$one" "decode 3 trailing arguments x argument 1"
assert "*  *   4" "$two" "decode 3 trailing arguments x argument 2"

# Test parsing safety

# $()
tmpfile=$(mktemp -ut poudriere_encode_args)
encode_args data "\$(touch ${tmpfile})"
[ -f "${tmpfile}" ]
assert_not 0 $? "File should not exist when encoded"
set -- bad bad bad bad bad
oldIFS="${IFS}"; IFS="${ENCODE_SEP}"; set -- ${data}; IFS="${oldIFS}"; unset oldIFS
[ -f "${tmpfile}" ]
assert_not 0 $? "File should not exist when decoded"
set -- bad bad bad bad bad
eval "$(decode_args data)"
[ -f "${tmpfile}" ]
assert_not 0 $? "File should not exist when decoded"

# ``
tmpfile=$(mktemp -ut poudriere_encode_args)
encode_args data "\`touch ${tmpfile}\`"
[ -f "${tmpfile}" ]
assert_not 0 $? "File should not exist when encoded"
[ -f "${tmpfile}" ]
assert_not 0 $? "File should not exist when decoded"
