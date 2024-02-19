# $FreeBSD: head/misc/freebsd-release-manifests/Makefile 429892 2016-12-29 12:41:04Z mat $

PORTNAME=	freebsd-release-manifests
DISTVERSION=	20161010
PORTREVISION=	0
# test/bulk-build-origin_has_pkgbase.sh depends on the ordering here such that
# foo comes after bar which comes after the first FLAVOR. More FLAVORS may be
# inserted anywhere.
FLAVORS=	default bar foo
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

.if ${FLAVOR} == foo
RUN_DEPENDS+=	foo:misc/foo
.endif

NO_BUILD=	yes
NO_ARCH=	yes

DATADIR=	${PREFIX}/share/freebsd

do-install:
	@${MKDIR} ${STAGEDIR}${DATADIR}/MANIFESTS
	${INSTALL_DATA} ${FILESDIR}/MANIFESTS/* \
	    ${STAGEDIR}${DATADIR}/MANIFESTS/

.include <bsd.port.mk>
