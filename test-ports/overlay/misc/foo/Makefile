# $FreeBSD: head/misc/freebsd-release-manifests/Makefile 429892 2016-12-29 12:41:04Z mat $

PORTNAME=	foo
DISTVERSION=	20161010
PORTREVISION=	0
PKGNAMESUFFIX=	-OVERLAY
FLAVORS=	default flav ignored_overlay
FLAVOR?=	default
.if ${FLAVOR} != default && !empty(FLAVORS:M${FLAVOR})
PKGNAMESUFFIX:=	${PKGNAMESUFFIX}-${FLAVOR:tu}
.endif
.if ${FLAVOR} == ignored_overlay
IGNORE=		ignored
.endif
CATEGORIES=	misc
MASTER_SITES=	#
DISTFILES=	#

MAINTAINER=	bdrewery@FreeBSD.org
COMMENT=	test port

LICENSE=	BSD2CLAUSE

NO_BUILD=	yes
NO_ARCH=	yes

do-install:
	@${MKDIR} ${STAGEDIR}${PREFIX}/foo/
	@${TOUCH} ${STAGEDIR}${PREFIX}/foo/bar

.include <bsd.port.mk>
