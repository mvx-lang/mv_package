#!/bin/sh
# install.sh — bootstrap the MVPKG client on jBASE FROM THIS ACCOUNT.
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see ../LICENSE).
#
# The jbase release IS an operator account: its BP holds the MVPKG client
# programs and the cut-down cmd framework.  Download it, then install in place:
#
#     tar xzf mvpkg-<ver>-jbase-any-any-le.tar.gz
#     cd mvpkg
#     . /opt/jbase/CurrentVersion/jbase_env.sh
#     ./install.sh
#
# All BASIC and shell -- no native code.  It:
#   1. give this directory the account furniture (MD, bin, lib)
#   2. write MVPKG.INC/PLATFORM.H, which the sources $INCLUDE
#   3. compile + catalog the client
#   4. provision the store and MVPKG init
#
# THREE WAYS jBASE IS NOT UniData, and each one shapes a step:
#
#   NO sudo, NO $UDTHOME.  jBASE catalogs PER USER -- a verb lands in ~/bin
#   (which is on PATH) and a subroutine in ~/lib/lib0.so -- so "global" here
#   means "this user, every account", and needs no privileged write.  There is
#   no system catalog directory to own or chown.
#
#   NO CallC aggregator.  UniData has to fold every package's C into one
#   libu2callc.so, which is why its installer ships udt-callc-build.  jBASE
#   reaches C with DEFC against an ordinary shared library, so there is nothing
#   central to rebuild and that whole step disappears.
#
#   CREATE-ACCOUNT REFUSES A NON-EMPTY DIRECTORY -- and an unpacked release is
#   never empty.  See below.
set -e

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

SCOPE=global; PREFIX=; _pfx_next=
for a in "$@"; do
   if [ -n "$_pfx_next" ]; then PREFIX="$a"; _pfx_next=; continue; fi
   case "$a" in
      --local|--direct) SCOPE=local ;;
      --global)         SCOPE=global ;;
      --prefix)         _pfx_next=1 ;;
      --prefix=*)       PREFIX="${a#--prefix=}" ;;
   esac
done
# The store this env owns.  $HOME, not a system directory: jBASE's catalog is
# already per user, so a per-user store keeps the whole install consistent and
# needs no privilege.
export MVPKG_STORE="${MVPKG_STORE:-$HOME/${PREFIX}mvpkg}"

say() { printf 'mvpkg-install: %s\n' "$1"; }
die() { printf 'mvpkg-install: %s\n' "$1" >&2; exit 1; }

[ -n "${JBCRELEASEDIR:-}" ] || die "JBCRELEASEDIR is not set — source jbase_env.sh first"
command -v jsh >/dev/null 2>&1 || die "jsh not on PATH — source jbase_env.sh first"
[ -d "$HERE/BP" ] || die "no BP/ here — run this from the unpacked mvpkg jbase account"
# MVPKG fetches over HTTP through the curl seam.  The OS curl satisfies
# curl-cmd; the libcurl package (mvx-lang/curl) needs no binary here.
command -v curl >/dev/null 2>&1 \
   || die "curl not found — MVPKG downloads packages over HTTP: sudo dnf install -y curl"

# 1) THE ACCOUNT FURNITURE.
#
# `CREATE-ACCOUNT <dir>` refuses outright if the directory has anything in it:
#
#     Unable to create the account; the directory is not empty!
#
# An unpacked release always does -- BP/, the manifest, this script.  So make
# the account in an EMPTY temporary directory and move its furniture across.
# That is jBASE's own tool doing the work, rather than this script guessing what
# an account is made of and getting it wrong when a release changes it.
if [ -e "$HERE/MD]D" ]; then
   say "account already provisioned (MD present)"
else
   say "creating the account furniture (MD, bin, lib)"
   TMPA=$(mktemp -d) || die "cannot make a temporary directory"
   ( cd "$TMPA" && CREATE-ACCOUNT "$TMPA" ) >/dev/null 2>&1 || true
   [ -e "$TMPA/MD]D" ] || { rm -rf "$TMPA"; die "CREATE-ACCOUNT did not produce an MD"; }
   cp -a "$TMPA/MD]D" "$HERE/" 2>/dev/null || true
   for d in bin lib; do
      [ -d "$TMPA/$d" ] && [ ! -d "$HERE/$d" ] && cp -a "$TMPA/$d" "$HERE/"
   done
   rm -rf "$TMPA"
   [ -e "$HERE/MD]D" ] || die "could not give this directory an MD"
fi

# 2) PLATFORM.H, before the compile: several BP records $INCLUDE it and a missing
#    include is a hard compile error -- while `MVPKG init`, which normally writes
#    it, cannot run until the client is cataloged.  Same content MVPKGOS INCSETUP
#    lays down, so a later `MVPKG init` is a no-op rather than a change.
say "writing MVPKG.INC/PLATFORM.H (before the compile: sources include it)"
mkdir -p "$HERE/MVPKG.INC"
cat > "$HERE/MVPKG.INC/PLATFORM.H" <<'PLATEOF'
* PLATFORM.H - jBASE platform defines.
* GENERATED FILE - DO NOT EDIT.  MVPKG INIT rewrites it,
* so any change made here is lost the next time it runs.
$DEFINE MV
$DEFINE JBASE
EQUATE MVMASTER TO "MD"
PLATEOF

# 3) compile + catalog.  Derived from BP/, never a hardcoded list: a hardcoded
#    one silently drops a newly added program, which is how CMD.FLAG went missing
#    from a cmd release and `GIT` failed with "Cannot find CMD.FLAG".
#    One BASIC per program -- a bulk compile is harder to read when one fails.
PROGS="$(cd "$HERE/BP" && for f in *; do [ -f "$f" ] && printf '%s ' "$f"; done)"
[ -n "$PROGS" ] || die "BP/ has no programs to compile"
say "compiling + cataloging the client (scope: $SCOPE)"
FAILED=
for p in $PROGS; do
   if ! ( cd "$HERE" && printf 'BASIC BP %s\n' "$p" | jsh 2>&1 ) | grep -q "compiled successfully"; then
      FAILED="$FAILED $p"
      continue
   fi
   ( cd "$HERE" && printf 'CATALOG BP %s\n' "$p" | jsh ) >/dev/null 2>&1 || true
done
[ -z "$FAILED" ] || die "compile failed for:$FAILED"

# A cataloged verb lands in ~/bin.  Check one rather than trusting the exit
# status: jsh reports a failed CATALOG on stdout and still exits 0.
[ -x "$HOME/bin/MVPKG" ] || die "catalog produced no ~/bin/MVPKG — is \$HOME/bin on PATH and writable?"
say "cataloged (MVPKG -> $HOME/bin/MVPKG)"
case ":$PATH:" in
   *":$HOME/bin:"*) ;;
   *) say "NOTE: $HOME/bin is not on PATH — add it, or the verbs will not be found" ;;
esac

# 4) the store, then MVPKG init (registry + store + this account's manifest).
say "provisioning the MVPKG store $MVPKG_STORE"
mkdir -p "$MVPKG_STORE"

INITFLAGS="-y"
[ "$SCOPE" = local ] && INITFLAGS="$INITFLAGS --local"
[ -n "$PREFIX" ] && INITFLAGS="$INITFLAGS --prefix $PREFIX"
say "MVPKG init ($INITFLAGS)"
( cd "$HERE" && printf 'MVPKG init %s\n' "$INITFLAGS" | jsh ) 2>&1 \
   | grep -iE "initialised|registry|store|include|catalog|prefix" | sed 's/^/  /' || true

say "done — run MVPKG from $HERE"
