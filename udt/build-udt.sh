#!/bin/sh
# build-udt.sh — stage the MVPKG udt release as a `mvpkg/` UniData account into $1.
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see ../LICENSE).
#
# MVPKG is all BASIC + shell — there is NO native code to compile, so unlike the
# git package this just ASSEMBLES the account tree (install.sh catalogs it in
# place at install time).  The tar wraps the one `mvpkg/` dir, so the release
# unpacks to a self-installing operator account:  cd mvpkg && ./install.sh
#
#   sh build-udt.sh <stagedir>
set -e
STAGE="${1:?usage: build-udt.sh <stagedir>}"
HERE="$(cd "$(dirname "$0")" && pwd)"        # the udt/ dir (client programs)
ROOT="$(cd "$HERE/.." && pwd)"               # repo root (PKG, mvpkg.json, LICENSE)
ACCT="$STAGE/mvpkg"
mkdir -p "$ACCT/BP"

# EVERY client program in the repo BP/, never a hardcoded list.  A hardcoded one
# silently drops a newly added program, and this one did: MVPKG.ENV, MVPKG.FILE,
# MVPKG.SH and MVPKG.SH.RM were in BP/ and in no release.  It went unseen because
# udt catalogs system-wide and jBASE per user, so on a machine that had ever
# installed mvpkg the missing programs were still resolvable from an older copy.
# A fresh account is where it surfaces -- "Unable to load subroutine MVPKG.ENV".
#
# Shared programs live canonically in BP/ as a single $IFDEF source; a program may
# still carry a platform-specific copy under udt/, which serves every non-mvx
# port.  Prefer that if present, else take BP/ -- so deleting udt/<prog> is what
# promotes it to canonical, with no further change here.  (MVPKGOS is exactly
# that case: BP/MVPKGOS is the mvx seam, udt/MVPKGOS serves udt, uv and jbase.)
for f in "$ROOT"/BP/*; do
   [ -f "$f" ] || continue
   p=$(basename "$f")
   # _<PROG> is a compiled object, not a program: UniData writes them beside
   # their source, so a repo that has been compiled in carries both.
   case "$p" in _*|.*) continue ;; esac
   if [ -f "$HERE/$p" ]; then cp "$HERE/$p" "$ACCT/BP/"; else cp "$f" "$ACCT/BP/"; fi
done

# udt-only records: the per-platform OS seam (MVPKGOS — mvx has its own in BP/),
# the udt deploy helper, the record include files, the bundled deps (native
# intrinsics on mvx), and the cmd framework.  (MVPKG.NOTIFY is now shared — the
# login update-notifier is platform-agnostic and builds for mvx too, issue #35.)
cp "$HERE"/MVPKGDEP \
   "$HERE"/MVPKG.LOCK.H "$HERE"/MVPKG.MANIFEST.H "$HERE"/MVPKG.CONF.H \
   "$HERE"/MVPKG.HTTPGET "$HERE"/MVPKG.HTTPGETFILE "$HERE"/MVPKG.JSONDECODE "$HERE"/MVPKG.MAPFIELD \
   "$HERE"/CALLC.EXISTS "$ACCT/BP/"
cp "$ROOT"/CMD.BP/CMD.INIT "$ROOT"/CMD.BP/CMD.ADD "$ROOT"/CMD.BP/CMD.RUN "$ACCT/BP/"

# The self-installer, the CallC aggregator it deploys, and the package metadata.
cp "$HERE"/install.sh          "$ACCT/install.sh";          chmod +x "$ACCT/install.sh"
cp "$HERE"/udt-callc-build.sh  "$ACCT/udt-callc-build.sh";  chmod +x "$ACCT/udt-callc-build.sh"
cp "$ROOT"/PKG "$ROOT"/mvpkg.json "$ROOT"/LICENSE "$ROOT"/README.md "$ACCT/" 2>/dev/null || true

# The version the release ships, into the manifests the release ships.  mvpkg
# REGISTERS ITSELF from PKG line 2, so a manifest the tag never touched makes it
# install one version and report another (mv_package#72).
. "$ROOT/version.sh"
mvpkg_stamp_manifests "$ACCT" "$(mvpkg_version "$ROOT")"

cat > "$ACCT/INSTALL.txt" <<'EOF'
MVPKG for Rocket UniData.  This directory IS the operator account.

Standalone install (no MVPKG yet — this bootstraps it):
  1. From inside this directory:  ./install.sh   (needs sudo for $UDTHOME)
     It newacct's this account, installs udt-callc-build, catalogs the client
     globally + the MVPKG verb locally, and runs MVPKG init.
  2. Then, in this account:  MVPKG install <name>
     Adopt a hand-installed package (e.g. git):  MVPKG register mvx-lang/git

Use a udt-recognised LANG (en_US.UTF-8), not C.UTF-8.
EOF
echo "build-udt: staged the mvpkg udt account as ./mvpkg/"
