# $FreeBSD: head/misc/freebsd-release-manifests/Makefile 429892 2016-12-29 12:41:04Z mat $

PORTNAME=	foo-flavor-double-DEPIGNORED
DISTVERSION=	20161010
PORTREVISION=	0
FLAVORS=	default depignored
FLAVOR?=	default
.if ${FLAVOR} != default && !empty(FLAVORS:M${FLAVOR})
PKGNAMESUFFIX=	-${FLAVOR:tu}
.endif
CATEGORIES=	misc
MASTER_SITES=	#
DISTFILES=	#

MAINTAINER=	bdrewery@FreeBSD.org
COMMENT=	FreeBSD release manifests

LICENSE=	BSD2CLAUSE

NO_BUILD=	yes
NO_ARCH=	yes

DATADIR=	${PREFIX}/share/freebsd
FILESDIR=	${.CURDIR:H:H}/misc/freebsd-release-manifests/files

.if ${FLAVOR} == depignored
RUN_DEPENDS+=	foo-dep-FLAVORS-unsorted-depignored:misc/foo-dep-FLAVORS-unsorted@depignored
RUN_DEPENDS+=	foo-all-IGNORED:misc/foo-all-IGNORED
.endif

do-install:
	@${MKDIR} ${STAGEDIR}${DATADIR}/MANIFESTS
	${INSTALL_DATA} ${FILESDIR}/MANIFESTS/* \
	    ${STAGEDIR}${DATADIR}/MANIFESTS/

.include <bsd.port.mk>
