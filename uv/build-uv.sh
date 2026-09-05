#!/bin/sh
# build-uv.sh — stage the MVPKG UniVerse release as a `mvpkg/` account into $1.
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see ../LICENSE).
#
# MVPKG is all BASIC and shell -- there is NO native code -- so this ASSEMBLES
# the account tree and uv/install.sh compiles and catalogs it in place at install
# time.  The tar wraps the one `mvpkg/` dir, so the release unpacks to a
# self-installing operator account:  cd mvpkg && ./install.sh
#
#   sh build-uv.sh <stagedir>
#
# The SAME sources as the udt and jbase accounts, because they are the same
# programs: one $IFDEF source per program, compiled for whichever platform
# PLATFORM.H names.  What differs is the installer -- UniVerse has to be told
# that BP is a file before it can compile from it, catalogs per account, and has
# no CallC aggregator, so udt-callc-build.sh is not staged here.
set -e
STAGE="${1:?usage: build-uv.sh <stagedir>}"
HERE="$(cd "$(dirname "$0")" && pwd)"        # the uv/ dir
ROOT="$(cd "$HERE/.." && pwd)"               # repo root
UDT="$ROOT/udt"                              # the shared non-mvx arm
ACCT="$STAGE/mvpkg"
rm -rf "$ACCT"
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
   if [ -f "$UDT/$p" ]; then cp "$UDT/$p" "$ACCT/BP/"; else cp "$f" "$ACCT/BP/"; fi
done

# The per-platform OS seam and the record includes.  CALLC.EXISTS comes too: it
# is a probe a package may call to ask whether native code is available, and it
# answers "no" perfectly well on a platform that has no route to C.
cp "$UDT"/MVPKGDEP \
   "$UDT"/MVPKG.LOCK.H "$UDT"/MVPKG.MANIFEST.H "$UDT"/MVPKG.CONF.H \
   "$UDT"/MVPKG.HTTPGET "$UDT"/MVPKG.HTTPGETFILE "$UDT"/MVPKG.JSONDECODE "$UDT"/MVPKG.MAPFIELD \
   "$UDT"/CALLC.EXISTS "$ACCT/BP/"
cp "$ROOT"/CMD.BP/CMD.INIT "$ROOT"/CMD.BP/CMD.ADD "$ROOT"/CMD.BP/CMD.RUN "$ACCT/BP/"

# EVERY STAGED BP ITEM GETS A TRAILING NEWLINE.  UniVerse's compiler rejects a
# source whose last line is unterminated -- "End of File unexpected" -- and the
# repo's items do not all have one, so this is not cosmetic: without it the
# target compiles nothing.  Appending only when it is missing keeps re-staging
# idempotent.
for f in "$ACCT/BP"/*; do
   [ -f "$f" ] || continue
   [ -n "$(tail -c 1 "$f")" ] && printf '\n' >> "$f"
done

cp "$HERE/install.sh" "$ACCT/install.sh"; chmod +x "$ACCT/install.sh"
cp "$ROOT"/PKG "$ROOT"/mvpkg.json "$ROOT"/LICENSE "$ROOT"/README.md "$ACCT/" 2>/dev/null || true

# The version the release ships, into the manifests the release ships.  mvpkg
# REGISTERS ITSELF from PKG line 2, so a manifest the tag never touched makes it
# install one version and report another (mv_package#72).
. "$ROOT/version.sh"
mvpkg_stamp_manifests "$ACCT" "$(mvpkg_version "$ROOT")"

# PLATFORM.H -- the compile-time defines the sources $INCLUDE as
# `$INCLUDE MVPKG.INC PLATFORM.H`.  BUILT HERE, not written by install.sh: it is
# build output, and build output belongs to the build.  Shipping it means the
# package carries exactly what will be compiled against, so it can be read in
# the tarball and diffed between releases.  It is the same content MVPKGOS
# INCSETUP writes, so a later `MVPKG init` is a no-op rather than a change.
#
# It ships at the package ROOT, not inside MVPKG.INC/: on the target MVPKG.INC
# has to be a VOC-registered file made by CREATE.FILE, and CREATE.FILE refuses
# when the directory is already there -- so install.sh creates the file and
# copies this in, rather than finding the directory pre-made and failing.
cat > "$ACCT/PLATFORM.H" <<'PLATEOF'
* PLATFORM.H - UniVerse (UV) platform defines.
* GENERATED FILE - DO NOT EDIT.  MVPKG INIT rewrites it,
* so any change made here is lost the next time it runs.
$DEFINE MV
$DEFINE UV
EQUATE MVMASTER TO "VOC"
PLATEOF

cat > "$ACCT/INSTALL.txt" <<'EOF'
MVPKG for Rocket UniVerse.  This directory IS the operator account.

Standalone install (no MVPKG yet — this bootstraps it):
  1. Set up the UniVerse environment so `uv` is on PATH.
  2. From inside this directory:  ./install.sh
     It makes this directory a UniVerse account, registers BP, BP.O and
     MVPKG.INC as UniVerse files, installs MVPKG.INC/PLATFORM.H, compiles and
     catalogs the client into this account, and runs MVPKG init.
  3. Then, in this account:  MVPKG install <name>

No sudo: UniVerse catalogs per account, so packages are cataloged LOCAL here and
the store lives under $HOME.  Run the installer in each account that needs MVPKG.
EOF
echo "build-uv: staged the mvpkg uv account as $ACCT/"
