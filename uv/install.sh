#!/bin/sh
# install.sh — bootstrap the MVPKG client on UniVerse FROM THIS ACCOUNT.
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see ../LICENSE).
#
# The uv release IS an operator account: its BP holds the MVPKG client programs
# and the cut-down cmd framework.  Download it, then install in place:
#
#     tar xzf mvpkg-<ver>-uv-linux-<arch>-le.tar.gz
#     cd mvpkg
#     ./install.sh
#
# All BASIC and shell -- no native code, and no sudo.  It:
#   1. make this directory a UniVerse account
#   2. register BP, BP.O and MVPKG.INC as UniVerse FILES, and install PLATFORM.H
#   3. compile + catalog the client into this account
#   4. provision the store and MVPKG init
#
# THREE WAYS UNIVERSE IS NOT UniData, and each one shapes a step:
#
#   AN UNPACKED DIRECTORY IS NOT AN ACCOUNT, AND A DIRECTORY IS NOT A FILE.
#   BP arrives as an ordinary directory of sources; until the VOC has a pointer
#   naming it, `BASIC BP *` cannot see it -- and says so by compiling nothing,
#   which reads exactly like success.
#
#   NO GLOBAL CATALOG WORTH USING.  UniData deploys a package by cataloging it
#   once system-wide and giving each account a VOC pointer to the object.
#   UniVerse's catalog space is laid out differently and its hashed directories
#   are not the $UDTHOME/sys/CTLG tree that MVPKGOS knows how to address -- so
#   here every account catalogs LOCALly, which is also what makes each program
#   typeable as a verb.  This installer therefore initialises local scope.
#
#   NO CallC AGGREGATOR.  BASIC has no in-process route to C on UniVerse (GCI
#   is licensed and dead in the Trial Edition), so there is nothing central to
#   relink and udt-callc-build is not shipped here.
set -e

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$HERE"

# Scope defaults to LOCAL, not global: see the note above.  --global is accepted
# so the flag exists, but MVPKGOS cannot address UniVerse's catalog space yet.
SCOPE=local; PREFIX=; _pfx_next=
for a in "$@"; do
   if [ -n "$_pfx_next" ]; then PREFIX="$a"; _pfx_next=; continue; fi
   case "$a" in
      --local|--direct) SCOPE=local ;;
      --global)         SCOPE=global ;;
      --prefix)         _pfx_next=1 ;;
      --prefix=*)       PREFIX="${a#--prefix=}" ;;
   esac
done
# The store this env owns.  $HOME, not a system directory: the catalog is
# per account here, so a per-user store keeps the whole install consistent
# and needs no privilege.  MVPKGOS resolves the same default.
export MVPKG_STORE="${MVPKG_STORE:-$HOME/${PREFIX}mvpkg}"

say() { printf 'mvpkg-install: %s\n' "$1"; }
die() { printf 'mvpkg-install: %s\n' "$1" >&2; exit 1; }

command -v uv >/dev/null 2>&1 \
   || die "uv is not on PATH — set up the UniVerse environment first"
[ -d "$HERE/BP" ] || [ -d "$HERE/BP.staged" ] \
   || die "no BP/ here — run this from the unpacked mvpkg uv account"
# MVPKG fetches over HTTP through the curl seam.  The OS curl satisfies
# curl-cmd; the libcurl package (mvx-lang/curl) needs no binary here.
command -v curl >/dev/null 2>&1 \
   || die "curl not found — MVPKG downloads packages over HTTP: sudo dnf install -y curl"

# 1) THE ACCOUNT.
#
# A fresh directory becomes one on its first `uv`, which asks whether to set it
# up and then for a flavour.  The packages target classic Pick, so the flavour is
# 3.  Unlike jBASE's CREATE-ACCOUNT this does NOT mind a directory with files
# already in it, so the unpacked release can be made an account where it stands.
# An existing account skips both prompts and the extra answers are harmless.
if [ ! -e VOC ]; then
   say "making this directory a UniVerse account (Pick flavour)"
   printf 'Y\n3\nQUIT\n' | uv >/dev/null 2>&1 || true
fi
[ -e VOC ] || die "could not create the account (no VOC)"

# 2) THE FILES.
#
# WHAT MAKES BP USABLE IS ITS VOC POINTER, not the directory on disk.  Those two
# come apart more often than they look like they should -- an account that was
# handed a copy of the package has D_BP sitting right there with no VOC record
# naming it -- so ask the VOC, which is the thing the compiler consults.
voc_has() {
   printf 'CT VOC %s\nQUIT\n' "$1" | uv 2>/dev/null | grep -q '^0001[[:space:]]*F'
}
# CREATE.FILE ASKS SEVEN QUESTIONS, not six: modulo, separation and type for the
# DICTionary, the same three for the DATA part, then a FILE DESCRIPTION.  That
# last one is the trap -- UniVerse stores it in VOC attribute 1 as "F <text>",
# and code that compares attribute 1 to "F" then cannot see the file at all.  So
# it is answered with an empty line, leaving a clean "F".
#   dict: modulo 1, separation 2, type 3  (hashed)
#   data: modulo 1, separation 2, type 19 (directory -- it holds source items)
mkfile() {
   printf 'CREATE.FILE %s\n1\n2\n3\n1\n2\n19\n\nQUIT\n' "$1" | uv >/dev/null 2>&1 || true
}
# Make $1 a real UniVerse file whatever state the directory is in.  CREATE.FILE
# builds the pointer, the dictionary and the directory TOGETHER and refuses when
# any of the three is already there -- so OS files with no pointer are debris in
# its way, and they go first.  $2, when given, is content to put back afterwards.
ensure_file() {
   voc_has "$1" && return 0
   say "registering $1 as a UniVerse file"
   if [ -n "${2:-}" ] && [ -d "$1" ]; then mv "$1" "$1.staged"; else rm -rf "$1"; fi
   rm -rf "D_$1"
   mkfile "$1"
   [ -e "$1" ] || die "CREATE.FILE did not create $1"
   if [ -d "$1.staged" ]; then
      for f in "$1.staged"/*; do [ -f "$f" ] && cp "$f" "$1/"; done
      rm -rf "$1.staged"
   fi
}

# BP holds the sources, so they are kept across the rebuild.
if ! voc_has BP && [ ! -d BP ] && [ -d BP.staged ]; then mv BP.staged BP; fi
ensure_file BP keep
# BP.O IS BUILD OUTPUT and is rebuilt rather than carried.  It also has to EXIST
# before the compiler runs: `BASIC BP *` creates it implicitly and cannot when an
# OS directory of that name is already there with no pointer naming it, after
# which nothing compiles.  Objects from somewhere else are worse than none --
# they run clean and are not the source beside them -- so they are dropped.
ensure_file BP.O
# MVPKG.INC before the compile: the sources $INCLUDE MVPKG.INC PLATFORM.H, and a
# missing include is a hard compile error -- while `MVPKG init`, which normally
# writes it, cannot run until the client is cataloged.
ensure_file MVPKG.INC

# PLATFORM.H comes from the BUILD, not from here -- the package ships the exact
# defines its sources were built against, and install puts them where the
# compiler looks.  Generating them here instead would mean the tarball and the
# installed account could disagree about what was compiled.  It is the same
# content MVPKGOS INCSETUP lays down, so a later `MVPKG init` is a no-op.
[ -f "$HERE/PLATFORM.H" ] \
   || die "PLATFORM.H is missing from this package — it is produced by build-uv.sh; this tarball was not built properly"
say "installing MVPKG.INC/PLATFORM.H (UniVerse platform defines)"
cp "$HERE/PLATFORM.H" MVPKG.INC/PLATFORM.H

# UniVerse's compiler rejects a source whose last line is unterminated -- "End of
# File unexpected".  The staged items already carry a trailing newline; a
# hand-edited one may not.
for f in BP/*; do
   [ -f "$f" ] || continue
   [ -n "$(tail -c 1 "$f")" ] && printf '\n' >> "$f"
done

# 3) compile + catalog.  Cataloged LOCAL, which is what registers each program
#    as a verb in this account as well as making its subroutines callable.
say "compiling the client"
printf 'BASIC BP *\nQUIT\n' | uv > /tmp/mvpkg-compile.$$ 2>&1 || true
NOK=$(grep -ac 'Compilation Complete' /tmp/mvpkg-compile.$$ || true)
NBAD=$(grep -ac 'Errors detected' /tmp/mvpkg-compile.$$ || true)
say "compiled $NOK program(s)"
if [ "${NBAD:-0}" -gt 0 ]; then
   printf 'mvpkg-install: %s program(s) failed to compile:\n' "$NBAD" >&2
   grep -aB3 'Errors detected' /tmp/mvpkg-compile.$$ | sed 's/^/    /' >&2
   rm -f /tmp/mvpkg-compile.$$
   exit 1
fi
rm -f /tmp/mvpkg-compile.$$

say "cataloging into this account (scope: $SCOPE)"
{ for p in $(ls BP); do echo "CATALOG BP $p LOCAL FORCE"; done; echo QUIT; } | uv >/dev/null 2>&1 || true
# Prove it rather than announce it: a failed CATALOG is reported on stdout and
# still exits 0, so check the VOC entry the catalog was supposed to leave.
# A LOCAL catalog leaves a VOC record of type "V" -- not the "C" UniData writes --
# with the object path in attribute 2.  That record is what makes the program
# both typeable as a verb and CALLable as a subroutine.
voc_has_verb() { printf 'CT VOC %s\nQUIT\n' "$1" | uv 2>/dev/null | grep -q '^0001[[:space:]]*V'; }
voc_has_verb MVPKG || die "MVPKG is not cataloged in this account — see the CATALOG output"
say "cataloged (MVPKG is a verb in this account)"

# 4) the store, then MVPKG init (registry + store + this account's manifest).
say "provisioning the MVPKG store $MVPKG_STORE"
mkdir -p "$MVPKG_STORE"

INITFLAGS="-y"
[ "$SCOPE" = local ] && INITFLAGS="$INITFLAGS --local"
[ -n "$PREFIX" ] && INITFLAGS="$INITFLAGS --prefix $PREFIX"
say "MVPKG init ($INITFLAGS)"
printf 'MVPKG init %s\nQUIT\n' "$INITFLAGS" | uv 2>&1 \
   | grep -iE "initialised|registry|store|include|catalog|prefix" | sed 's/^/  /' || true

say "done — LOGTO this account and run MVPKG"
