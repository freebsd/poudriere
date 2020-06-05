CPDUP -- Filesystem Mirroring Utility
=====================================

Introduction
------------
The `cpdup` utility makes an exact mirror copy of the source in the
destination, creating and deleting files and directories as necessary.
UTimes, hardlinks, softlinks, devices, permissions, and flags are
mirrored.  By default, `cpdup` asks for confirmation if any file or directory
needs to be removed from the destination and does not copy files which it
believes to have already been synchronized (by observing that the source
and destination files' sizes and mtimes match).  `cpdup` does not cross
mount points in either the source or the destination.  As a safety
measure, `cpdup` refuses to replace a destination directory with a file.

The `cpdup` utility was originally created to update servers at
BEST Internet circa 1997 and was placed under the FreeBSD copyright for
inclusion in the [Ports Collection](https://www.freebsd.org/ports/) in 1999.
This utility was written by Matthew Dillon, Dima Ruban, and later
significantly improved by Oliver Fromme.

Upstream source:
[DragonFly BSD's `bin/cpdup`](https://gitweb.dragonflybsd.org/dragonfly.git/tree/HEAD:/bin/cpdup)

Manual page: [`cpdup(1)`](https://www.dragonflybsd.org/cgi/web-man?command=cpdup&section=1)

Platforms
---------
* DragonFly BSD
* FreeBSD
* NetBSD
* Linux (tested on Arch Linux and CentOS)

(Welcome to help test on and port to more platforms)

Installation
------------
1.  Install dependencies:

    * `make` (GNU make)
    * `gcc`
    * `pkg-config`
    * `libbsd-dev` (Required only on Linux)
    * `libssl-dev` (OpenSSL/LibreSSL)

    Arch Linux: `pacman -S pkgconf libbsd openssl`

    CentOS: `yum install pkgconfig libbsd-devel openssl-devel`

    Debian: `apt install pkg-config libbsd-dev libssl-dev`

    DragonFly BSD / FreeBSD: `pkg install gmake pkgconf libressl`

2.  Build: `make`

3.  Install: `sudo make install [PREFIX=/usr/local]`

Packages
--------
**Arch Linux**:

    $ make archpkg
    $ sudo pacman -U cpdup-*.pkg.*

**CentOS**:

    $ make rpm
    $ sudo rpm -ivh cpdup-*.rpm

License
-------
[The 3-Clause BSD License](LICENSE)
