# $FreeBSD: head/Mk/Uses/gettext.mk 373636 2014-11-29 18:22:32Z tijl $
#
# Sets a library dependency on gettext-runtime and a build dependency
# on gettext-tools.  Same as "USES=gettext-runtime gettext-tools".
#
# Feature:	gettext
# Usage:	USES=gettext
#
# MAINTAINER:	portmgr@FreeBSD.org

.if !defined(_INCLUDE_USES_GETTEXT_MK)
_INCLUDE_USES_GETTEXT_MK=	yes

.if !empty(gettext_ARGS)
IGNORE=		USES=gettext does not take arguments
.endif

.include "${USESDIR}/gettext-runtime.mk"
.include "${USESDIR}/gettext-tools.mk"

.endif
