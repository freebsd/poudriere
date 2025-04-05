# Shared library tracking

## Purpose

Poudriere has 2 incremental build modes.

1. Rebuild everything downstream if a dependency is missing or changed. This is the **curent default**.
2. Only rebuild what `pkg upgrade` would [re]install for, but also ensure build reproducibility. Enabled with `PKG_NO_VERSION_FOR_DEPS=yes`.
  - **Guiding principle is to only rebuild what `pkg upgrade` would upgrade for; build for `pkg upgrade` behavior.**
  - In that sense the current algorithm rebuilds _a lot_ that `pkg upgrade` does not care about; we rebuild a lot needlessly.

This document describes the algorithm for (2) with shared libraries.

## Brief overview of the new algorithm

This belongs in another document but is here for context as that document does not yet exist.

For `PKG_NO_VERSION_FOR_DEPS=yes` we do not store the versions for dependencies. If a dependency `foo-1.2` used to be registered but was bumped to `foo-1.3` it used to force a rebuild because the dependency was missing. Now we only store `foo` as a dependency, such that version bumps do not themselves force a rebuild.

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

Further it is possible that this package requires a shared library that no dependency provides for. Due to the lack of ports metadata advertising what libraries are provided we must search dependency packages _after they are built_ to determine if this package still has its shared library requirements met. That is, some of `_delete_old_pkg` (inspection of existing package) for shared library handling is deferred to the build.

## Shared library missed PORTREVISION chase / Branch switch

These cases are the target of this algorithm:
- A committer updates a port providing a shared library, with a new shared library version, and forgets to bump its consumers (or assumes Poudriere will deal with rebuilding everything).
  - In this case the packages will remain installed on user systems but new installs of the packages will not find a package providing for one of their needed libraries.
  - This is the "missed PORTREVISION chase" case.
- **Switching branch / quarterly switches** which a committer cannot deal with; we do not want to bump _everything_.
- User has local custom ports using libraries that cannot be chased by upstream.

### Notes

- It is also possible that a port uses a shared library from a nested dependency and lacks a `LIB_DEPENDS` on it.
- Ports like php/pecl pop up on this algorithm often.
- This algorithm results in "Inspected" ports during the build.
- This algorithm results in the "do we need to rebuild" decision for many packages being deferred to the build phase.
- This may occur for every build and result in a NOP build still inspecting hundreds of packages.
- This may need to be extended to _incremental-alg-1_ as well with `AUTO_LIB_DEPENDS`.
- This may already be enabled for _incremental-alg-1_ by default somewhat by accident.

### Algorithm

**The primary goal here is to rebuild only if needed and not miss it when needed.**

1. During build planning if a package uses shared libraries, and nothing else in `delete_old_pkg` triggers a rebuild, then it is scheduled to be "inspected" later after its own dependencies have been built/inspected.
  - See `delete_old_pkg`.
  - The "it" and "this package" and "_old/stale_ package" is the same one referred below.
  - We stash the list of current shlibs required by this _old/stale_ package.
  - Base libraries, ones provided in the jail's clean snapshot, are removed from the list. It is assumed that a jail version update will force rebuild all packages.
2. Later during the build we run the inspection job for a particular port `libfooconsumer`.
  - We find that this port still has an _old/stale_ package that was not deleted.
  - We do not yet know if it will rebuild.
  - The package version matches the port's version.
3. The existing package is used to build a full recursive runtime dependency graph _from that package_.
  - See `package_recursive_deps`.
  - Ports metadata is not used as this package is _old/stale_ and does not match _current_ ports.
  - _This package_ is the _old/stale_ one but its dependencies are _potentially newly built_ packages since this job runs after they are inspected/rebuilt.
  - This is somewhat expensive and uses caching. It adds minutes to a NOP build (`bulk -a` has not been timed).
  - Wishlist: ports providing metadata on what libraries they provide. This would allow more predictable build planning, but could still become stale.
  - **This is no longer possible with `AUTO_LIB_DEPENDS`.**
4. Then construct a full list of shared libraries provided by that graph.
  - This involves looking at the shared libraries provided by each _current/new_ package.
  - This creates a new _current effective_ graph that `pkg upgrade` / `pkg install` would see if we were to not rebuild this package.
  - See `package_deps_provided_libs`.
5. Then compare this _old/stale_ package's required shlibs to see if they are still satisfied or if a rebuild is needed.
  - See `package_libdeps_satisfied`.
  - Inspect each library provided for by its _current effective_ package-runtime dependency graph.
  - If a package provides a needed shlib by exact name, success, we move on to the next library.
  - If a package provides a library that "looks like" a shared lib we need then we rebuild. For example, we want libfoo.so.1 and libfoo.pkg now provides libfoo.so.2, close enough, rebuild.
  - If we have a required library that _no dependency provides for_ a rebuild is done, but it may be a bug in the port.
    - For example this was fixed in a `go` port in [freebsd/freebsd-ports@a4327166148114](https://github.com/freebsd/freebsd-ports/commit/a4327166148114c314ae5dd6f9c7e6776178e0ac).
  - If all exact library names were satisfied then no rebuild is done.

### Examples

```
Warning: couchdb3-3.4.2 will be rebuilt as it misses libcrypto.so.12
Warning: couchdb3-3.4.2_1 will be rebuilt as it misses libcrypto.so.12
Warning: couchdb3-3.4.3_1 will be rebuilt as it misses libcrypto.so.12
Warning: emacs-nox-29.4_2,3 will be rebuilt as it misses libtree-sitter.so.0.24
Warning: fusefs-bindfs-1.17.7_1 will be rebuilt as it misses libfuse3.so.3
Warning: fusefs-sshfs-3.7.3_2 will be rebuilt as it misses libfuse3.so.3
[false-positive+bug] Warning: go122-1.22.11 will be rebuilt as it misses libc.so.6:32
[false-positive+bug] Warning: go123-1.23.5 will be rebuilt as it misses libc.so.6:32
[false-positive+bug] Warning: go123-1.23.6 will be rebuilt as it misses libc.so.6:32
Warning: mold-2.36.0 will be rebuilt as it misses libmimalloc.so.2
Warning: mosh-1.4.0_8 will be rebuilt as it misses libabsl_bad_optional_access.so.2407.0.0
Warning: node18-18.20.6 will be rebuilt as it misses libicudata.so.74
Warning: protobuf-c-1.5.1 will be rebuilt as it misses libabsl_bad_optional_access.so.2407.0.0
[These are custom ports that cannot be chased by upstream committers]
Warning: znc16-1.6.6_4 will be rebuilt as it misses libicudata.so.74
Warning: znc17-1.7.5_2 will be rebuilt as it misses libboost_locale.so.1.85.0
Warning: znc17-1.7.5_2 will be rebuilt as it misses libboost_locale.so.1.86.0
Warning: znc17-1.7.5_2 will be rebuilt as it misses libicudata.so.74
Warning: znc18-1.8.2_12 will be rebuilt as it misses libboost_locale.so.1.85.0
Warning: znc18-1.8.2_12 will be rebuilt as it misses libboost_locale.so.1.86.0
Warning: znc18-1.8.2_12 will be rebuilt as it misses libicudata.so.74
```

Ignored ones:
```
apache24-2.4.62 misses libdb-18.1.so which no dependency provides. This will be ignored but should be fixed in the port.
bootstrap-openjdk17-17.0.1.12.1 misses libX11.so.6 which no dependency provides. This will be ignored but should be fixed in the port.
bootstrap-openjdk17-17.0.1.12.1 misses libXext.so.6 which no dependency provides. This will be ignored but should be fixed in the port.
bootstrap-openjdk17-17.0.1.12.1 misses libXi.so.6 which no dependency provides. This will be ignored but should be fixed in the port.
bootstrap-openjdk17-17.0.1.12.1 misses libXrender.so.1 which no dependency provides. This will be ignored but should be fixed in the port.
bootstrap-openjdk17-17.0.1.12.1 misses libXtst.so.6 which no dependency provides. This will be ignored but should be fixed in the port.
bootstrap-openjdk17-17.0.1.12.1 misses libasound.so.2 which no dependency provides. This will be ignored but should be fixed in the port.
bootstrap-openjdk17-17.0.1.12.1 misses libfontconfig.so.1 which no dependency provides. This will be ignored but should be fixed in the port.
bootstrap-openjdk17-17.0.1.12.1 misses libfreetype.so.6 which no dependency provides. This will be ignored but should be fixed in the port.
bootstrap-openjdk17-17.0.1.12.1 misses libgif.so.7 which no dependency provides. This will be ignored but should be fixed in the port.
bootstrap-openjdk17-17.0.1.12.1 misses libharfbuzz.so.0 which no dependency provides. This will be ignored but should be fixed in the port.
bootstrap-openjdk17-17.0.1.12.1 misses libjpeg.so.8 which no dependency provides. This will be ignored but should be fixed in the port.
bootstrap-openjdk17-17.0.1.12.1 misses liblcms2.so.2 which no dependency provides. This will be ignored but should be fixed in the port.
bootstrap-openjdk17-17.0.1.12.1 misses libpng16.so.16 which no dependency provides. This will be ignored but should be fixed in the port.
couchdb3-3.4.2 misses libcrypto.so.12 which no dependency provides. This will be ignored but should be fixed in the port.
neovim-0.10.3_1 misses /usr/local/lib/lua/5.1/lpeg.so which no dependency provides. This will be ignored but should be fixed in the port.
serf-1.3.10_1 misses libdb-18.1.so which no dependency provides. This will be ignored but should be fixed in the port.
```

## Pkg `AUTO_LIB_DEPENDS` discussion

This discussion is not a suggesting that `AUTO_LIB_DEPENDS` is a problem or we need to continue tracking something, it is to ensure the right behavior is planned for.

With Pkg 2.1 `AUTO_LIB_DEPENDS` it no longer will advertise packages in run depends that only provide a library. This causes problems for [Algorithm.3](./shlib_tracking.md#Algorithm) as we no longer know what the current package's _old_ graph is.

What we can do instead is use the port's current `RUN_DEPENDS+LIB_DEPENDS` as a guide, assuming that the port is reproducible, that its libraries are still provided for. If nothing in its new graph provides the needed library then it may be reasonable to make it a hard error, or force a rebuild, rather than ignoring it in poudriere.

`RUN_DEPENDS` are considered as well given they may provide a library that port picks up on despite the metadata/maintainer not realizing it.

It seems wrong to use the current port's `RUN_DEPENDS+LIB_DEPENDS` when inspecting an existing _old/stale_ package. This may not be a real concern when considering the port claims it wants those and we are determining whether a rebuild is needed in a case where the port was _not_ bumped. **The package would match the port's version at this point.**

However, when considering the behavior of `pkg upgrade` here the algorithm becomes less clear. This may be getting into the weeds and overcomplicating the ideas but it seems reasonable to keep in mind `pkg upgrade`'s behavior when building ports.

Consider odd unpredictable cases like `gettext-*` refactoring that force manual intervention at ports or pkg. And keep in mind branch-switching and user custom ports. A `libfooconsumer.pkg` may want a `libfoo.so.1` which `libfoo.pkg` provided. Then for whatever reason `libfoo.pkg` no longer provides it but a `libfoo-compat.pkg` now provides it. And `libfooconsumer`'s port `RUN_DEPENDS+LIB_DEPENDS` were not updated. Assume we do not rebuild `libfooconsumer` here - `pkg upgrade` will gladly pull in `libfoo-compat.pkg` to satisfy `libfooconsumer`'s need of `libfoo.so.1`. Because `pkg upgrade` dealt with it fine and the `libconsumer` port did not _need a rebuild_ should we still delete it and attempt a rebuild? It may fail and result in a lost package for the user.

In such a case it does not matter what the current port's `RUN_DEPENDS+LIB_DEPENDS` are. It matters what libraries are provided for _by the repository_. It is possible we do not need to rebuild. That the port's metadata is stale and rebuilding it will just break it when we could have kept the user happy with a working repository by not rebuilding it. In such a case we need to inspect _every package_ that built before this one. We do not have a pkg repository to inspect, it does not make sense to run `pkg repo` during every package build. We could cache each package's provided libraries as they are built and serialize access to it.

There is a subtle problem too in that if we assume `libfoo-compat.pkg` will satisfy, it may not have built by the time `libfooconsumer` is scheduled if it was not in the graph. So we get to `libfooconsumer` and don't find anyone provides `libfoo.so.1` and rebuild anyway. This problem may be a deal breaker for this odd case discussion; we may just have to use current `RUN_DEPENDS+LIB_DEPENDS`.
