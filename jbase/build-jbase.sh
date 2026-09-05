#!/bin/sh
# build-jbase.sh — stage the MVPKG jBASE release as a `mvpkg/` account into $1.
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see ../LICENSE).
#
# MVPKG is all BASIC and shell -- there is NO native code -- so this ASSEMBLES
# the account tree and jbase/install.sh catalogs it in place at install time.
# The tar wraps the one `mvpkg/` dir, so the release unpacks to a self-installing
# operator account:  cd mvpkg && ./install.sh
#
#   sh build-jbase.sh <stagedir>
#
# The SAME sources as the udt account, because they are the same programs: one
# $IFDEF source per program, compiled for whichever platform PLATFORM.H names.
# What differs is the installer -- jBASE catalogs per user and has no CallC
# aggregator, so udt-callc-build.sh is not staged here.
set -e
STAGE="${1:?usage: build-jbase.sh <stagedir>}"
HERE="$(cd "$(dirname "$0")" && pwd)"        # the jbase/ dir
ROOT="$(cd "$HERE/.." && pwd)"               # repo root
UDT="$ROOT/udt"                              # the shared non-mvx arm
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
   if [ -f "$UDT/$p" ]; then cp "$UDT/$p" "$ACCT/BP/"; else cp "$f" "$ACCT/BP/"; fi
done

# The per-platform OS seam and the record includes.  CALLC.EXISTS comes too: it
# is a probe a package may call to ask whether native code is available, and it
# answers "no" perfectly well on a platform with no CallC.
ACCTBP="$ACCT/BP"
# AND EVERY udt/ PROGRAM THAT HAS NO BP/ COUNTERPART.  The per-platform OS seam
# and the record includes live only there, and they used to be named one by one
# -- so MVPKG.HTTPPOST, added for install reporting, staged on no platform at
# all and the client compiled without it.  Same lesson as the loop above: derive
# it.  Non-programs (the shell scripts and the build's own files) are skipped by
# extension; anything else in udt/ is a BASIC item and belongs in BP/.
for f in "$UDT"/*; do
   [ -f "$f" ] || continue
   p=$(basename "$f")
   case "$p" in (*.sh|_*|.*) continue ;; esac
   [ -f "$ACCTBP/$p" ] || cp "$f" "$ACCTBP/"
done
cp "$ROOT"/CMD.BP/CMD.INIT "$ROOT"/CMD.BP/CMD.ADD "$ROOT"/CMD.BP/CMD.RUN "$ACCT/BP/"

# THE HTTP SEAM NEEDS THE NAME jBASE WILL LOOK FOR.  U2 points a local name at a
# differently-named cataloged one with `DEFFUN ... CALLING`; jBASE has no such
# clause (it is a syntax error there), so its DEFFUN is bare and resolves by
# NAME.  mvpkg ships MVPKG.HTTPGET, nothing answered to HTTPGET, and every fetch
# died -- including the fetch of the curl-cmd package that was meant to provide
# the name (#77).  ALL FOUR names MVPKG.META declares that way need one, not
# just the HTTP pair: a clean $HOME/lib showed MAPFIELD failing exactly the same
# way once no earlier install had left a copy behind.  Each forwards to mvpkg's
# own seam, and the real package (curl-cmd, json, mapfield) catalogs its own
# over the wrapper later, same name and same signature.
cp "$HERE"/HTTPGET "$HERE"/HTTPGETFILE "$HERE"/JSONDECODE "$HERE"/MAPFIELD "$ACCT/BP/"

cp "$HERE/install.sh" "$ACCT/install.sh"; chmod +x "$ACCT/install.sh"
# The shared-object search-path helper.  install.sh puts it in the store, where
# MVPKGOS reaches it from any account -- the way UniData's CallC builder sits in
# $UDTHOME/bin.
cp "$HERE/mvpkg-jblib" "$ACCT/mvpkg-jblib"; chmod +x "$ACCT/mvpkg-jblib"
cp "$ROOT"/PKG "$ROOT"/mvpkg.json "$ROOT"/LICENSE "$ROOT"/README.md "$ACCT/" 2>/dev/null || true

# The version the release ships, into the manifests the release ships.  mvpkg
# REGISTERS ITSELF from PKG line 2, so a manifest the tag never touched makes it
# install one version and report another (mv_package#72).
. "$ROOT/version.sh"
mvpkg_stamp_manifests "$ACCT" "$(mvpkg_version "$ROOT")"

cat > "$ACCT/INSTALL.txt" <<'EOF'
MVPKG for jBASE.  This directory IS the operator account.

Standalone install (no MVPKG yet — this bootstraps it):
  1. Source the jBASE environment:  . /opt/jbase/CurrentVersion/jbase_env.sh
  2. From inside this directory:    ./install.sh
     It gives this directory the account furniture (MD, bin, lib), writes
     MVPKG.INC/PLATFORM.H, compiles + catalogs the client, and runs MVPKG init.
  3. Then, in this account:  MVPKG install <name>

No sudo: jBASE catalogs per user — verbs land in ~/bin and subroutines in
~/lib/lib0.so — so $HOME/bin must be on PATH.
EOF
echo "build-jbase: staged the mvpkg jbase account as $ACCT/"
