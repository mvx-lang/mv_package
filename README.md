# mv_package

A package manager for MultiValue — Composer/npm for the PICK world. A **pure
MultiValue BASIC client** (`MVPKG`) talks to a small **Node.js registry** over
HTTP, resolves a package, downloads its release tar archive and installs it
into an account.

The repository **is** an MVX account (an mvx-git account, like
[ev_eb](https://github.com/mvx-lang/ev_eb)): `VOC/` and `BP/` are directory
files, so every record is a plain tracked file and the working tree is the live
account — there is nothing to import.

## Two ways to get a package

- **Release (binary).** `MVPKG install <name>` downloads a pre-built release
  tar from the registry and unpacks it whole. The client never inspects or
  compiles the contents, so a release may be **binary-only** — pre-built
  `CATALOG/` executables and `LIB/` libraries with no `BP/` source at all — and
  installs exactly like one that ships source.
- **Dev / source.** Clone the package's own mvx-git repository and build it with
  the target platform's toolchain. This is the source-and-compile path (as
  `mvx-git` is ported to more MV systems); it is not what `MVPKG install` does.

## The client — `MVPKG`

Commands are case-insensitive (MV developers work with Caps Lock on):

```
MVPKG install <name> [<dest>]   install a package and its dependencies
                                (<dest> defaults to a directory named <name>)
MVPKG info <name>               show a package's registry metadata
MVPKG search <term>             list packages whose name/description matches
MVPKG setup <url>               set (and persist) the registry base URL
MVPKG config                    show the current registry URL
```

`install` resolves the package's **dependencies** first: a package names the
packages it needs in its registry metadata, and the client installs the
whole transitive set, dependencies before dependents. Installed package
names are recorded in `mvpkg.installed` in the account, so a dependency
already present is not reinstalled. On UniData this means installing an app
that depends on `curses` pulls the native bridge in and rebuilds the shared
library — one command, nothing manual.

**Dependency syntax.** Each entry in the `dependencies` list is a package name
with two optional suffixes, `name[@system][:constraint]`:

- `@system` — a platform gate. `name@udt,mvx` applies only on those systems;
  `name@!mvx` applies everywhere *except* those. A package built into the
  runtime on one platform declares the fallback for the others, e.g.
  `mapfield@!mvx` (MAPFIELD is a builtin on MVX, a package on UniData).
- `:constraint` — a version constraint, Composer/npm style:
  `mapfield:^1.2` (>=1.2.0 <2.0.0), `~1.4.0` (>=1.4.0 <1.5.0), `>=1.0,<2.0`
  (comma = AND), `1.2.*`, an exact `1.4.2`, or `*` for any. The client picks
  the **newest published version** satisfying it.

Both may appear together: `mapfield@!mvx:^1.0`.

**Release channels.** A registry version is *stable* unless it carries a
pre-release suffix (`1.3.0-beta.1`, `2.0.0-rc.2`, `1.0.0-dev`). The default
"latest" a bare `MVPKG install <name>` (or an unconstrained dependency)
resolves to is always the newest **stable** release, so following a stable
series is the default — a published beta never pulls anyone off it. To opt in
to a pre-release, pin it exactly (`MVPKG install thing` then a version
constraint referencing it) or write a constraint whose lower bound is itself a
pre-release, e.g. `thing:^1.3.0-beta` matches `1.3.0-beta.1`, `1.3.0-rc.1`,
and the eventual `1.3.0`.

The registry URL is taken from `$MVPKG_REGISTRY`, then a persisted `mvpkg.conf`,
then the built-in default (`https://mv-package.heydon.io`).

**Portability.** The only non-MultiValue operations — unpacking a tar, making a
directory — go through the `MVPKGOS` subroutine, the one per-platform seam. HTTP
itself is a language extension on MVX (the `http` package: `HTTPGET` /
`HTTPGETFILE`); another MV system supplies its own equivalents. The rest of
`MVPKG` is portable BASIC.

**UniData port** (`udt/`). UniData has neither the HTTP nor the JSON
intrinsics, so the port fills both seams — `udt/HTTPGET` and
`udt/HTTPGETFILE` via `curl`, and `udt/JSONDECODE` + `udt/MAPFIELD` as a
minimal flat-JSON decoder (enough for the registry's metadata) — and
`udt/MVPKG` is the client in UniData idiom (`@SENTENCE`, `GETENV`, `OSREAD`
statements) declaring those seams as cataloged functions. `MVPKG install`
then runs on UniData: it fetches the release, unpacks it, and — for a
package that ships a `udt-callc/` contribution — rebuilds the shared CallC
library, all in one command (see below). `search` awaits a fuller JSON seam
(issue #4).

## The registry

The registry service, website, and release/build tooling live in their own
repository — **[mv-package-registry](https://github.com/mvx-lang/mv-package-registry)**
— so installing the client doesn't pull in the server. It is live at
**https://mv-package.heydon.io**: browse packages there, or hit the JSON API
the client speaks (`/package/<name>`, `/search`, `/tarball/…`). Publishing a
release and hosting your own registry are documented in that repo.

## Manifest

A package's registry metadata mirrors MVX's `PKG` fields (`name`, `version`,
`description`, a `dependencies` list — space-separated, each entry
`name[@system][:constraint]` as above — and, for resolution across platforms,
a `systems` list). `mkrelease.sh` takes the dependencies as its fifth
argument. The release tar carries the account's own `.mvx` / `PKG`.

## Native code on UniData — the shared CallC library

Some packages reach into the host through native C: on UniData that means
functions compiled into **CallC**, which UniData exposes to BASIC as `CALLC
NAME(...)`. UniData loads exactly **one** `libu2callc.so`, so native add-ons
cannot each own it — they must be **aggregated**. mv_package owns that
library on UniData.

A package that compiles into UniData ships a `udt-callc/` directory — its
contribution:

```
udt-callc/
  *.c      C sources compiled into the library (or *.o for a binary release)
  funcs    cfuncdef declarations, one per line: name:rettype:nargs:argtypes
  libs     optional: a line of extra linker flags for this package
```

`MVPKG install` unpacks the release and then calls `MVPKGOS("CALLC", …)`; the
UniData port stages the contribution into `$UDTHOME/callc.d/<pkg>/` and
rebuilds `libu2callc.so` from **every** contribution installed — so adding
one package never disturbs another, and removing one and rebuilding drops it
cleanly (the system base functions are re-injected automatically). `MVPKG
rebuild` re-runs that aggregation on demand.

The rebuild lives in [`udt/udt-callc-build.sh`](udt/udt-callc-build.sh),
installed to `$UDTHOME/bin/udt-callc-build` by the UniData setup and driven
by [`udt/MVPKGOS`](udt/MVPKGOS). On MVX these ops are no-ops: native code is
an ordinary compiled subroutine library that installs as-is, with nothing to
aggregate.

### Checking a capability without installing it

A program that uses an optional native add-on when present must be able to
ask *before* using it — and that check must work on an account where the
add-on was never installed. A CallC to an unregistered function aborts the
whole program (no trappable error), so the probe cannot itself be a CallC.
[`udt/CALLC.EXISTS`](udt/CALLC.EXISTS) is pure BASIC: it reads the canonical
CallC definition and returns 1/0, never invoking anything.

The UniData setup ([`udt/setup.sh`](udt/setup.sh)) catalogs it **globally**,
so it is present on every account regardless of what is installed. A program
guards on it and runs either way:

```basic
   DEFFUN CALLC.EXISTS(A)
   IF CALLC.EXISTS("CURSINIT") THEN
      GOSUB FULL.SCREEN.UI        ;* udt_curses is installed — use it
   END ELSE
      GOSUB PLAIN.UI             ;* runs on a bare account too
   END
```

Only `CALLC.EXISTS` itself must exist, and the setup guarantees it does. Set
up a UniData host once with:

```sh
UDTHOME=/usr/ud83 ./udt/setup.sh /path/to/an/account
```

which installs the aggregator and catalogs the probe. See the reference
add-on [udt_curses](https://github.com/mvx-lang/udt_curses) (mv_package
issues #2, #3).

## Build and test

```sh
MVX_HOME=/path/to/mvx-lang ./build.sh        # catalog MVPKG + MVPKGOS
```

`build.sh` needs an mvx-lang checkout with a built toolchain (the `http` and
`json` extension packages are installed by default). Installing runs `tar`
through `EXECUTE "!..."`, so it needs the unrestricted privilege tier
(`MVXPRIV=unrestricted`) — installing software is inherently privileged. The
end-to-end install-loop test (client + registry) lives in the
[registry repo](https://github.com/mvx-lang/mv-package-registry).

## License

GPL-2.0-only. See [LICENSE](LICENSE).
