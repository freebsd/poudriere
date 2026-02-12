# New Incremental Mode

## Overview

Poudriere has 2 incremental build modes

1. Rebuild everything downstream if a dependency is missing or changed. This is the **curent default**.
2. Only rebuild what `pkg upgrade` would [re]install for, but also ensure build reproducibility. Enabled with `PKG_NO_VERSION_FOR_DEPS=yes`.
  - **Guiding principle is to only rebuild what `pkg upgrade` would upgrade for; build for `pkg upgrade` behavior.**
  - In that sense the current algorithm rebuilds _a lot_ that `pkg upgrade` does not care about; we rebuild a lot needlessly.

This document describes the algorithm for (2).

## Current algorithm

The current default behavior is to recursively delete all packages that depend
on a package that is updated. This effectively forces a `PORTREVISION` chase on
those packages.

A major flaw with this is that a package will often rebuild while having the same
version as it did before. Then `pkg upgrade` has no clue there is a _rebuilt_
package available to upgrade to, and it does nothing. So we are building packages
that never get used unless someone does `pkg install -f pkgname`.

## New algorithm

[Commit 6c8c538f](https://github.com/freebsd/poudriere/commit/6c8c538ffcad3b88bc807b15cc69acc6c72d8962)
introduced a new mode named `PKG_NO_VERSION_FOR_DEPS`.

For `PKG_NO_VERSION_FOR_DEPS=yes` we do not store the versions for
dependencies. If a dependency `foo-1.2` used to be registered but was bumped to
`foo-1.3` it used to force a rebuild because the dependency was missing. Now we
only store `foo` as a dependency, such that version bumps do not themselves
force a rebuild.

Always rebuild cases are:

```
# _delete_old_pkg():
# We delete [a package] and force a rebuild in these cases:
# - pkg bootstrap is not available
# - FORBIDDEN is set for the port
# - Corrupted package file
# - bulk -a: A package which the tree no longer creates.
#   For example, a package with a removed FLAVOR.
# - Wrong origin cases:
#   o MOVED: origin moved to a new location
#   o MOVED: origin expired
#   o Nonexistent origin
#   o A package with the wrong origin for its PKGNAME
# - Changed PKGNAME
# - PORTVERSION, PORTREVISION, or PORTEPOCH bump.
# - Changed ABI/ARCH/NOARCH
# - FLAVOR for a PKGNAME changed
# - New list of dependencies (not including versions)
#   (requires default-on CHECK_CHANGED_DEPS)
# - Changed options
#   (requires default-on CHECK_CHANGED_OPTIONS)
#
# These are handled by pkg (pkg_jobs_need_upgrade()) but not Poudriere yet:
#
# - changed conflicts		# not used by ports
# - changed provides		# not used by ports
# - changed requires		# not used by ports
# - changed provided shlibs	# effectively by CHECK_CHANGED_DEPS
# - changed required shlibs	# effectively by CHECK_CHANGED_DEPS
```

Further it is possible that this package requires a shared library that no
dependency provides for. This can happen due to a missed `PORTREVISION` chase
or simply switching to a new quarterly branch. Due to the lack of ports
metadata advertising what libraries are provided we must search dependency
packages _after they are built_ to determine if this package still has its
shared library requirements met. That is, some of `_delete_old_pkg` (inspection
of existing package) for shared library handling is deferred to the build.

This changes Poudriere behavior in a few ways:

- Dry-run mode can no longer predict everything that will be done.
- A new "inspected" category is added. A port is "inspected" to see if its shared library dependencies are satisified. If they are then it is done. If they are not then it rebuilds that package.
- `PORTREVISION` bumps are now critical. The old behavior of recursively deleting hid how important these are as it often would rebuild things anyway. Now we basically only rebuild if the version or a required shared library version changed.

More details on shared library handling are in [shlib_tracking.md](./shlib_tracking.md).

## `PKG_NO_VERSION_FOR_DEPS` safety

Removing the versions from the dependencies is likely safe for a single
consistent repository. For multi-repository support we likely need more work
for binary-dependencies (like `RUN_DEPENDS+= /usr/local/bin/foo:devel/fooport`)
or provides/requires.

Missed `PORTREVISION` chases can lead to very confusing `pkg upgrade`
conflicts/behavior and runtime problems.
