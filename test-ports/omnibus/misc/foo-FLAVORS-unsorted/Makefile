# $FreeBSD: head/misc/freebsd-release-manifests/Makefile 429892 2016-12-29 12:41:04Z mat $

PORTNAME=	foo-FLAVORS-unsorted
DISTVERSION=	20161010
PORTREVISION=	0
FLAVORS=	flav default ignored depignored
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

BUILD_DEPENDS+=	foo:misc/foo-dep-FLAVORS-unsorted@${FLAVOR}

.include <bsd.port.options.mk>

.if empty(FLAVOR)
FLAVOR=	default
.endif

.if ${FLAVOR} != default && !empty(FLAVORS:M${FLAVOR})
PKGNAMESUFFIX=	-${FLAVOR:tu}
.endif
.if ${FLAVOR} == ignored
IGNORE=		ignored
.endif

do-install:
	@${MKDIR} ${STAGEDIR}${DATADIR}/MANIFESTS
	${INSTALL_DATA} ${FILESDIR}/MANIFESTS/* \
	    ${STAGEDIR}${DATADIR}/MANIFESTS/

.include <bsd.port.mk>
