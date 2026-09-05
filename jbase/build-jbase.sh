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
   if [ -f "$UDT/$p" ]; then cp "$UDT/$p" "$ACCT/BP/"; else cp "$f" "$ACCT/BP/"; fi
done

# The per-platform OS seam and the record includes.  CALLC.EXISTS comes too: it
# is a probe a package may call to ask whether native code is available, and it
# answers "no" perfectly well on a platform with no CallC.
cp "$UDT"/MVPKGDEP \
   "$UDT"/MVPKG.LOCK.H "$UDT"/MVPKG.MANIFEST.H "$UDT"/MVPKG.CONF.H \
   "$UDT"/MVPKG.HTTPGET "$UDT"/MVPKG.HTTPGETFILE "$UDT"/MVPKG.JSONDECODE "$UDT"/MVPKG.MAPFIELD \
   "$UDT"/CALLC.EXISTS "$ACCT/BP/"
cp "$ROOT"/CMD.BP/CMD.INIT "$ROOT"/CMD.BP/CMD.ADD "$ROOT"/CMD.BP/CMD.RUN "$ACCT/BP/"

cp "$HERE/install.sh" "$ACCT/install.sh"; chmod +x "$ACCT/install.sh"
cp "$ROOT"/PKG "$ROOT"/mvpkg.json "$ROOT"/LICENSE "$ROOT"/README.md "$ACCT/" 2>/dev/null || true

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
