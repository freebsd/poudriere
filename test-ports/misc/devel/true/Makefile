# $FreeBSD$

PORTNAME=	true
PORTVERSION=	20170609
CATEGORIES=	devel

MAINTAINER=	bdrewery@FreeBSD.org
COMMENT=	You can't handle the truth

LICENSE=	BSD2CLAUSE
LICENSE_FILE=	${WRKSRC}/LICENSE
LIB_DEPENDS=	libtrue.so:devel/libtrue

DISTFILES=	#
MASTER_SITES=	#
LIBTRUE_SRC=	${.CURDIR}/../libtrue/files/libtrue
BUILD_WRKSRC=	${WRKSRC}/true

do-extract:
	${MKDIR} ${WRKSRC}
	${TAR} -cf - -C ${LIBTRUE_SRC} . | ${TAR} -xf - -C ${WRKSRC}

do-install:
	${MKDIR} ${STAGEDIR}${PREFIX}/bin ${STAGEDIR}/bin
	${INSTALL_PROGRAM} ${WRKSRC}/true/true ${STAGEDIR}${PREFIX}/bin/

.include <bsd.port.mk>
