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
MVPKG install <name> [<dest>]   download the release tar, install into <dest>
                                (<dest> defaults to a directory named <name>)
MVPKG info <name>               show a package's registry metadata
MVPKG search <term>             list packages whose name/description matches
MVPKG setup <url>               set (and persist) the registry base URL
MVPKG config                    show the current registry URL
```

The registry URL is taken from `$MVPKG_REGISTRY`, then a persisted `mvpkg.conf`,
then the built-in default (`http://127.0.0.1:8080`).

**Portability.** The only non-MultiValue operations — unpacking a tar, making a
directory — go through the `MVPKGOS` subroutine, the one per-platform seam. HTTP
itself is a language extension on MVX (the `http` package: `HTTPGET` /
`HTTPGETFILE`); another MV system supplies its own equivalents. The rest of
`MVPKG` is portable BASIC.

## The registry — `server/`

A dependency-free Node.js HTTP registry (the packagist/npm-registry
equivalent). Packages live under `server/registry/<name>/` as a `meta.json`
beside the release tar it points at. Routes:

```
GET /package/<name>    that package's metadata
GET /search?q=<term>   {"packages":[{name,version,description}, ...]}
GET /tarball/<file>    the release tar bytes
```

Run it, and register a release built from any account:

```sh
node server/server.js 8080
server/mkrelease.sh /path/to/account <name> <version> "<description>"
```

## Manifest

A package's registry metadata mirrors MVX's `PKG` fields (`name`, `version`,
`description`, and — for resolution across platforms — a `systems` list). The
release tar carries the account's own `.mvx` / `PKG`.

## Build and test

```sh
MVX_HOME=/path/to/mvx-lang ./build.sh        # catalog MVPKG + MVPKGOS
MVX_HOME=/path/to/mvx-lang ./test/run.sh     # end-to-end install-loop test
```

`build.sh` needs an mvx-lang checkout with a built toolchain (the `http` and
`json` extension packages are installed by default). Installing runs `tar`
through `EXECUTE "!..."`, so it needs the unrestricted privilege tier
(`MVXPRIV=unrestricted`) — installing software is inherently privileged.

## License

GPL-2.0-only. See [LICENSE](LICENSE).
