#! /bin/sh

. common.sh
. ${SCRIPTPREFIX}/common.sh
PORTSDIR=${THISDIR}/port_var_fetch
export PORTSDIR

# The "." port is the only one in our pseudo PORTSDIR.

port_var_fetch "." \
    PKGNAME pkgname
assert "py34-sqlrelay-1.0.0_2" "${pkgname}" "PKGNAME"

# Try a lookup on a missing variable and ensure the value is cleared
blah="notcleared"
port_var_fetch "." \
    BLAH blah
assert "" "${blah}" "blah variable not cleared on missing result"

pkgname=
port_var_fetch "." \
    PKGNAME pkgname
assert "py34-sqlrelay-1.0.0_2" "${pkgname}" "PKGNAME"

port_var_fetch "." \
	FOO='BLAH BLAH ${PKGNAME}' \
	PKGNAME pkgname \
	FOO foo \
	BLAH='blah' \
	IGNORE ignore \
	_PDEPS='${PKG_DEPENDS} ${EXTRACT_DEPENDS} ${PATCH_DEPENDS} ${FETCH_DEPENDS} ${BUILD_DEPENDS} ${LIB_DEPENDS} ${RUN_DEPENDS}' \
	_PDEPS pdeps \
	_UNKNOWN unknown \
	'${_PDEPS:C,([^:]*):([^:]*):?.*,\2,:C,^${PORTSDIR}/,,:O:u}' \
	pkg_deps
assert 0 $? "port_var_fetch should succeed"

assert "py34-sqlrelay-1.0.0_2" "${pkgname}" "PKGNAME"
assert "BLAH BLAH py34-sqlrelay-1.0.0_2" "${foo}" "FOO should have been overridden"
assert "test ignore 1 2 3" "${ignore}" "IGNORE"
assert "/usr/local/sbin/pkg:ports-mgmt/pkg /nonexistent:databases/sqlrelay:patch perl5>=5.20<5.21:lang/perl5.20  gmake:devel/gmake /usr/local/bin/python3.4:${PORTSDIR}/lang/python34 perl5>=5.20<5.21:lang/perl5.20 /usr/local/bin/ccache:devel/ccache libsqlrclient.so:${PORTSDIR}/databases/sqlrelay /usr/local/bin/python3.4:lang/python34" \
    "${pdeps}" "_PDEPS"
assert "" "${unknown}" "_UNKNOWN"
assert "databases/sqlrelay devel/ccache devel/gmake lang/perl5.20 lang/python34 ports-mgmt/pkg" \
    "${pkg_deps}" "PKG_DEPS eval"

pkgname=
port_var_fetch "foo" \
    PKGNAME pkgname 2>/dev/null
assert 1 $? "port_var_fetch invalid port should fail"
assert "" "${pkgname}" "PKGNAME shouldn't have gotten a value in a failed lookup"

pkgname=
port_var_fetch "." \
    FAIL=1 \
    PKGNAME pkgname 2>/dev/null
assert 1 $? "port_var_fetch with FAIL set should fail"
assert "" "${pkgname}" "PKGNAME shouldn't have gotten a value in a failed lookup"
