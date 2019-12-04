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

* [![FreeBSD 11.2 amd64](https://api.cirrus-ci.com/github/freebsd/poudriere.svg?task=freebsd11-amd64&branch=master)](https://cirrus-ci.com/github/freebsd/poudriere)
* [![FreeBSD 12.0 amd64](https://api.cirrus-ci.com/github/freebsd/poudriere.svg?task=freebsd12-amd64&branch=master)](https://cirrus-ci.com/github/freebsd/poudriere)
* [![FreeBSD 13.0 amd64](https://api.cirrus-ci.com/github/freebsd/poudriere.svg?task=freebsd13-amd64&branch=master)](https://cirrus-ci.com/github/freebsd/poudriere)
