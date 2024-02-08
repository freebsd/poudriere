# $FreeBSD: head/misc/freebsd-release-manifests/Makefile 429892 2016-12-29 12:41:04Z mat $

PORTNAME=	foo
DISTVERSION=	20161010
PORTREVISION=	0
FLAVORS=	default flav ignored
FLAVOR?=	default
.if ${FLAVOR} != default && !empty(FLAVORS:M${FLAVOR})
PKGNAMESUFFIX=	-${FLAVOR:tu}
.endif
.if ${FLAVOR} == ignored
IGNORE=		ignored
.endif
CATEGORIES=	misc
MASTER_SITES=	#
DISTFILES=	#

MAINTAINER=	bdrewery@FreeBSD.org
COMMENT=	foo test port

LICENSE=	BSD2CLAUSE

NO_BUILD=	yes
NO_ARCH=	yes

DATADIR=	${PREFIX}/share/freebsd

do-install:
	@${ECHO} "#! /bin/sh" > ${STAGEDIR}${PREFIX}/bin/foo
	@${CHMOD} +x ${STAGEDIR}${PREFIX}/bin/foo

.include <bsd.port.mk>
