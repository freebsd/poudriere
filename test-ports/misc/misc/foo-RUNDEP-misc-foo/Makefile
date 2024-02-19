# $FreeBSD: head/misc/freebsd-release-manifests/Makefile 429892 2016-12-29 12:41:04Z mat $

PORTNAME=	foo-RUNDEP-misc-foo
DISTVERSION=	20161010
PORTREVISION=	0
FLAVORS=	flav default ignored depignored
CATEGORIES=	misc
MASTER_SITES=	#
DISTFILES=	#

MAINTAINER=	bdrewery@FreeBSD.org
COMMENT=	FreeBSD release manifests

LICENSE=	BSD2CLAUSE

USES=		metaport

NO_BUILD=	yes
NO_ARCH=	yes

RUN_DEPENDS+=	foo:misc/foo@default

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
	@${DO_NADA}

.include <bsd.port.mk>
