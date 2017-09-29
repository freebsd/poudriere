# bsd.local.mk - Sandbox for local modification to ports framework.
#
# Created by: Mark Linimon <linimon@FreeBSD.org>
#
# $FreeBSD: head/Mk/bsd.local.mk 358214 2014-06-18 07:14:22Z bapt $
#

.if !defined(_POSTMKINCLUDED) && !defined(Local_Pre_Include)

Local_Pre_Include=	bsd.local.mk

#
# Here is where any code that needs to run at bsd.port.pre.mk inclusion
# time should live.
#

.endif # !defined(_POSTMKINCLUDED) && !defined(Local_Pre_Include)

.if defined(_POSTMKINCLUDED) && !defined(Local_Post_Include)

Local_Post_Include=	bsd.local.mk

#
# here is where any code that needs to run at bsd.port.post.mk inclusion
# time should live.
#

.endif # defined(_POSTMKINCLUDED) && !defined(Local_Post_Include)
