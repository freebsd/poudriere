# $FreeBSD: head/misc/freebsd-release-manifests/Makefile 429892 2016-12-29 12:41:04Z mat $

PORTNAME=	foo
DISTVERSION=	20161010
PORTREVISION=	0
FLAVORS=	default flav ignored broken
FLAVOR?=	default
.if ${FLAVOR} != default && !empty(FLAVORS:M${FLAVOR})
PKGNAMESUFFIX=	-${FLAVOR:tu}
.endif
.if ${FLAVOR} == ignored
IGNORE=		ignored
.elif ${FLAVOR} == broken
BROKEN=		broken
.endif
CATEGORIES=	misc
MASTER_SITES=	#
DISTFILES=	#

OPTIONS_DEFINE=	FOOBIN FAILURE SLEEP RENAME
FOOBIN_DESC=	Provide bin/foo
FAILURE_DESC=	Cause a failure during install
SLEEP_DESC=	Sleep before build to increase queue race test
RENAME_DESC=	Change PKGNAME
OPTIONS_DEFAULT=FOOBIN
OPTIONS_SUB=	yes

.include <bsd.port.options.mk>

.if ${PORT_OPTIONS:MRENAME}
PKGNAMESUFFIX:=	${PKGNAMESUFFIX}-renamed
.endif

MAINTAINER=	bdrewery@FreeBSD.org
COMMENT=	foo test port

LICENSE=	BSD2CLAUSE

NO_ARCH=	yes

DATADIR=	${PREFIX}/share/freebsd

do-build:
	@${MKDIR} ${WRKDIR}

# Sleep 1 minute load average + some time. Trying to build after
# ports-mgmt/poudriere-devel-dep-FOO is done; which will fail in
# run-depends if we succeed in not building. If we build before
# it gets to run-depends it will pass and the test will XPASS.
do-build-SLEEP-on:
	set -x; \
	    load="$$(uptime | sed -E -e 's,.*load averages: ([0-9][0-9]?[0-9]?).*,\1,')"; \
	    sleep $$((load + 40))

do-install:
	@${DO_NADA}

do-install-FOOBIN-on:
	@${ECHO} "#! /bin/sh" > ${STAGEDIR}${PREFIX}/bin/foo
	@${CHMOD} +x ${STAGEDIR}${PREFIX}/bin/foo

do-install-FAILURE-on:
	@${ECHO} "FAILURE defined. Causing failure."
	${FALSE}

.include <bsd.port.mk>
