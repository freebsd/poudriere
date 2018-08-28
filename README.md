Welcome to poudriere!
---------------------

poudriere is a tool primarily designed to test package production on
FreeBSD. However, most people will find it useful to bulk build ports
for FreeBSD.

Its goals are to use modern facilities present in FreeBSD (such as ZFS,
jails), to be easy to use and to depend only on base.

Where is the documentation?
---------------------------

The canonical documentation is located at:

https://github.com/freebsd/poudriere/wiki

A copy of this documentation could be found in the doc directory.

You can also open the poudriere's manpage, located in the 8th section.

Support
-------

IRC:          [#poudriere](https://webchat.freenode.net/?channels=%23poudriere) on freenode  
Mailing list: [freebsd-pkg@FreeBSD.org (lists.freebsd.org)](https://lists.freebsd.org/mailman/listinfo/freebsd-pkg)

Getting started with poudriere
------------------------------

1. Install it by typing `./configure`, `make` and `make install` at the top-level directory
2. Copy `/usr/local/etc/poudriere.conf.sample` to `/usr/local/etc/poudriere.conf`
3. Edit it to suit your needs
4. `man poudriere`, search for `EXAMPLES`, read the [wiki](https://github.com/freebsd/poudriere/wiki)
5. Follow "bulk build of binary packages" steps
6. Enjoy your new fresh binary packages!

Build status
------------------------------

* i386 [![FreeBSD i386](https://jenkins.mouf.net/job/poudriere/label=i386/badge/icon)](https://jenkins.mouf.net/job/poudriere/label=i386)
* amd64 [![FreeBSD amd64](https://jenkins.mouf.net/job/poudriere/label=amd64/badge/icon)](https://jenkins.mouf.net/job/poudriere/label=amd64)
* armv6 [![FreeBSD armv6](https://jenkins.mouf.net/job/poudriere/label=armv6/badge/icon)](https://jenkins.mouf.net/job/poudriere/label=armv6)
* armv7 [![FreeBSD armv7](https://jenkins.mouf.net/job/poudriere/label=armv7/badge/icon)](https://jenkins.mouf.net/job/poudriere/label=armv7)
* aarch64 [![FreeBSD aarch64](https://jenkins.mouf.net/job/poudriere/label=aarch64/badge/icon)](https://jenkins.mouf.net/job/poudriere/label=aarch64)
* powerpc64 [![FreeBSD powerpc64](https://jenkins.mouf.net/job/poudriere/label=powerpc64/badge/icon)](https://jenkins.mouf.net/job/poudriere/label=powerpc64)
