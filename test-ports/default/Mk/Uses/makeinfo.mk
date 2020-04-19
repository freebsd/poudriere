# $FreeBSD: head/Mk/Uses/makeinfo.mk 520033 2019-12-13 13:48:55Z adamw $
#
# handle dependency on the makeinfo port
#
# Feature:	makeinfo
# Usage:	USES=makeinfo
# Valid ARGS:	none
#
# MAINTAINER: portmgr@FreeBSD.org

.if !defined(_INCLUDE_USES_MAKEINFO_MK)
_INCLUDE_USES_MAKEINFO_MK=	yes

.if !empty(makeinfo_ARGS)
IGNORE=	USES=makeinfo - expects no arguments
.endif

# Depend specifically on makeinfo from ports
BUILD_DEPENDS+=	${LOCALBASE}/bin/makeinfo:print/texinfo
MAKEINFO?=	${LOCALBASE}/bin/makeinfo

.endif
