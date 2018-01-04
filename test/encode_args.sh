#! /bin/sh

. common.sh
. ${SCRIPTPREFIX}/include/util.sh

encode_args data "1"
assert "1" "${data}" "encode 1 argument"

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
eval $(decode_args data)
assert 2 $# "decode 2 argument argcnt"
assert "1" "$1" "decode 2 argument argument 1"
assert "2 3" "$2" "decode 2 argument argument 2"

# Test embedded cmdsubst
TMP=$(mktemp -ut encoded_args)
encode_args data "\$(touch ${TMP})"
assert "\$(touch ${TMP})" "${data}" "encoded cmdsubst"
eval $(decode_args data)
[ -f "${TMP}" ]
assert 1 $? "decoding cmdsubst should not fire: ${TMP}"

# Test 1 trailing empty arguments
encode_args data "1" ""
assert "1${ENCODE_SEP}${ENCODE_SEP}" "${data}" "encode 1 trailing args"
eval $(decode_args data)
assert 2 $# "decode 1 trailing arguments argcnt"
assert "1" "$1" "decode 1 trailing arguments argument 1"
assert "" "$2" "decode 1 trailing arguments argument 2"

# Test trailing empty arguments
encode_args data "1" "" "" ""
assert "1${ENCODE_SEP}${ENCODE_SEP}${ENCODE_SEP}${ENCODE_SEP}" "${data}" "encode 3 trailing args"
eval $(decode_args data)
assert 4 $# "decode 3 trailing arguments argcnt"
assert "1" "$1" "decode 3 trailing arguments argument 1"
assert "" "$2" "decode 3 trailing arguments argument 2"
assert "" "$3" "decode 3 trailing arguments argument 3"
assert "" "$4" "decode 3 trailing arguments argument 4"

# Test trailing empty arguments with data
encode_args data "1" "" "" "x"
assert "1${ENCODE_SEP}${ENCODE_SEP}${ENCODE_SEP}x" "${data}" "encode 3 trailing args x"
eval $(decode_args data)
assert 4 $# "decode 3 trailing arguments x argcnt"
assert "1" "$1" "decode 3 trailing arguments x argument 1"
assert "" "$2" "decode 3 trailing arguments x argument 2"
assert "" "$3" "decode 3 trailing arguments x argument 3"
assert "x" "$4" "decode 3 trailing arguments x argument 4"

# Test parsing safety

# $()
tmpfile=$(mktemp -ut poudriere_encode_args)
encode_args data "\$(touch ${tmpfile})"
[ -f "${tmpfile}" ]
assert_not 0 $? "File should not exist when encoded"
eval $(decode_args data)
[ -f "${tmpfile}" ]
assert_not 0 $? "File should not exist when decoded"

# ``
tmpfile=$(mktemp -ut poudriere_encode_args)
encode_args data "\`touch ${tmpfile}\`"
[ -f "${tmpfile}" ]
assert_not 0 $? "File should not exist when encoded"
[ -f "${tmpfile}" ]
assert_not 0 $? "File should not exist when decoded"
