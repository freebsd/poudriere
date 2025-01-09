# $FreeBSD$

PORTNAME=	libtrue
PORTVERSION=	20170609
CATEGORIES=	devel

MAINTAINER=	bdrewery@FreeBSD.org
COMMENT=	You can't handle the truth

LICENSE=	BSD2CLAUSE
LICENSE_FILE=	${WRKSRC}/LICENSE

DISTFILES=	#
MASTER_SITES=	#
LIBTRUE_SRC=	${.CURDIR}/../libtrue/files/libtrue
BUILD_WRKSRC=	${WRKSRC}/libtrue

OPTIONS_DEFINE+=	SHLIB_BUMP
SHLIB_BUMP_DESC=	Bump shlib major version and PORTEPOCH
.include <bsd.port.options.mk>
.if ${PORT_OPTIONS:MSHLIB_BUMP}
LIBTRUE_VER=	1
# PORTEPOCH is bumped just so bulk test makes it a bit more obvious something
# unexpected compared to normal ports checkout is happening.
PORTEPOCH=	9
.else
LIBTRUE_VER=	0
.endif

MAKE_ENV+=	LIBTRUE_VER=${LIBTRUE_VER}
PLIST_SUB+=	LIBTRUE_VER="${LIBTRUE_VER}"
do-extract:
	${MKDIR} ${WRKSRC}
	${TAR} -cf - -C ${LIBTRUE_SRC} . | ${TAR} -xf - -C ${WRKSRC}

do-install:
	${MKDIR} ${STAGEDIR}${PREFIX}/lib
	${INSTALL_DATA} ${WRKSRC}/libtrue/libtrue.a ${STAGEDIR}${PREFIX}/lib/
	${INSTALL_LIB} ${WRKSRC}/libtrue/libtrue.so ${STAGEDIR}${PREFIX}/lib/
	${INSTALL_LIB} ${WRKSRC}/libtrue/libtrue.so.${LIBTRUE_VER} \
	    ${STAGEDIR}${PREFIX}/lib/
	${INSTALL_DATA} ${WRKSRC}/libtrue/true.h ${STAGEDIR}${PREFIX}/include/

.include <bsd.port.mk>
