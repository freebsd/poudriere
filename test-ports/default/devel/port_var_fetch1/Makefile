# make -VPKG_DEPENDS -VBUILD_DEPENDS -VEXTRACT_DEPENDS -VLIB_DEPENDS -VPATCH_DEPENDS -VFETCH_DEPENDS -VRUN_DEPENDS
PKGNAME=	py34-sqlrelay-1.0.0_2
IGNORE=		test ignore 1 2 3
PKG_DEPENDS=	/usr/local/sbin/pkg:ports-mgmt/pkg
BUILD_DEPENDS=	gmake:devel/gmake /usr/local/bin/python3.4:${PORTSDIR}/lang/python34 perl5>=5.20<5.21:lang/perl5.20 /usr/local/bin/ccache:devel/ccache
EXTRACT_DEPENDS=/nonexistent:databases/sqlrelay:patch
LIB_DEPENDS=	libsqlrclient.so:${PORTSDIR}/databases/sqlrelay
PATCH_DEPENDS=	perl5>=5.20<5.21:lang/perl5.20
FETCH_DEPENDS=	
RUN_DEPENDS=	/usr/local/bin/python3.4:lang/python34
FOO=		foo
.if !empty(FAIL)
.error FAIL
.endif
