#!/bin/sh
# install.sh — bootstrap the MVPKG client on Rocket UniData FROM THIS ACCOUNT.
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see ../LICENSE).
#
# The udt release IS an operator account: its BP holds the MVPKG client programs
# and the cut-down cmd framework.  Download it, then install in place — the same
# shape as the git package, so the package MANAGER is itself a PICK account you
# install from:
#
#     tar xzf mvx-lang_mvpkg-<ver>-udt.tar.gz
#     cd mvpkg
#     ./install.sh                 # needs sudo for $UDTHOME + a UniData login
#
# All BASIC/shell — no native code to compile.  It:
#   1. newacct this dir so udt can LOGTO it (this becomes the operator account)
#   2. install udt-callc-build -> $UDTHOME/bin (the CallC aggregator packages use)
#   3. globally catalog the probes (CALLC.EXISTS, MVPKG.HAS) and the client
#      helpers; MVPKG itself is a LOCAL verb typed in this account
#   4. MVPKG init (records the registry + store + this account's manifest)
#
# Env: UDTHOME (default /usr/ud83), UDT_OWNER/UDT_GROUP (newacct owner; default
# the invoking user), LANG (a udt-recognised locale; default en_US.UTF-8 — NOT
# C.UTF-8, which udt rejects).
set -e

UDTHOME="${UDTHOME:-/usr/ud83}"
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LANG_OK="${LANG:-en_US.UTF-8}"; case "$LANG_OK" in C.UTF-8|POSIX|C) LANG_OK=en_US.UTF-8 ;; esac
OWNER="${UDT_OWNER:-${SUDO_USER:-$(id -un)}}"
GROUP="${UDT_GROUP:-$(id -gn "$OWNER" 2>/dev/null || id -gn)}"
UDT="$UDTHOME/bin/udt"

say() { printf 'mvpkg-install: %s\n' "$1"; }
die() { printf 'mvpkg-install: %s\n' "$1" >&2; exit 1; }
[ -d "$UDTHOME" ] && [ -x "$UDT" ] || die "UDTHOME=$UDTHOME is not a UniData install (set UDTHOME)"
command -v sudo >/dev/null 2>&1 || die "sudo not found — needed for \$UDTHOME writes"
# MVPKG fetches packages over HTTP through the curl seam (UniData's native HTTPS
# doesn't reliably reach github + follow redirects), so curl is a prerequisite.
command -v curl >/dev/null 2>&1 || die "curl not found — MVPKG downloads packages over HTTP with curl: sudo dnf install -y curl"
[ -d "$HERE/BP" ] || die "no BP/ here — run this from the unpacked mvpkg udt account"

# 1) make this dir a real UniData account (idempotent) — the operator account
if [ -e "$HERE/VOC" ]; then
  say "account already provisioned (VOC present)"
else
  say "provisioning UniData operator account here (owner $OWNER:$GROUP)"
  ( cd "$HERE" && printf 'y\n%s\n%s\n' "$OWNER" "$GROUP" | "$UDTHOME/bin/newacct" ) >/dev/null \
    || die "newacct failed — run it by hand in $HERE to see the prompt"
fi

# 2) the CallC aggregator every native package uses to (re)build libu2callc.so
say "installing udt-callc-build -> $UDTHOME/bin"
sudo install -m 755 "$HERE/udt-callc-build.sh" "$UDTHOME/bin/udt-callc-build"

# 3) catalog the probes + client GLOBALLY (default; there is NO GLOBAL keyword),
#    MVPKG LOCALLY.  A piped udt exits 0 even when an inner command fails, so
#    verify by a catalog entry rather than trusting the exit code.
PROBES="CALLC.EXISTS MVPKG.HAS"
GLOBAL="MVPKGOS MVPKGDEP HTTPGET HTTPGETFILE JSONDECODE MAPFIELD SEMVER \
CMD.INIT CMD.ADD CMD.RUN MVPKG.REG MVPKG.META MVPKG.ONE \
MVPKG.INSTALL MVPKG.INFO MVPKG.LIST MVPKG.UPDATE MVPKG.REMOVE \
MVPKG.REGISTER MVPKG.SEARCH MVPKG.SETUP MVPKG.CONFIG MVPKG.REBUILD MVPKG.INIT"
say "compiling + cataloging the client (globals + probes) and the MVPKG verb"
# One BASIC per program, not one BASIC with a long arg list: `BASIC BP <many
# args>` segfaults udt on this UniData (it still writes the objects, but the
# session dies before the CATALOGs run).  Per-program compile is clean.
{
  for p in $PROBES $GLOBAL MVPKG; do echo "BASIC BP $p"; done
  for p in $PROBES $GLOBAL; do echo "CATALOG BP $p FORCE"; done
  echo "CATALOG BP MVPKG LOCAL FORCE"
  echo "QUIT"
} | ( cd "$HERE" && LANG="$LANG_OK" TERM=dumb "$UDT" ) >/dev/null 2>&1 || true
ls "$UDTHOME"/sys/CTLG/*/MVPKGOS >/dev/null 2>&1 \
  || die "catalog failed — check LANG (not C.UTF-8) and write access to $UDTHOME/sys/CTLG"
say "cataloged (MVPKGOS -> $(ls "$UDTHOME"/sys/CTLG/*/MVPKGOS 2>/dev/null | head -1))"

# 4) provision the MVPKG store.  It defaults to $UDTHOME/mvpkg (a system location
#    so every operator account shares one package store), but $UDTHOME is
#    DBA-owned — so create it and hand it to the operator, else MVPKG (running as
#    that user) can't write the manifest and every list shows nothing.
STORE="${MVPKG_STORE:-$UDTHOME/mvpkg}"
say "provisioning the MVPKG store $STORE (owner $OWNER:$GROUP)"
sudo mkdir -p "$STORE"
sudo chown "$OWNER:$GROUP" "$STORE"

# 5) initialise MVPKG (registry + store + this account's manifest)
say "MVPKG init"
( cd "$HERE" && printf 'MVPKG init\nQUIT\n' | LANG="$LANG_OK" TERM=dumb "$UDT" ) 2>&1 \
  | grep -iE "initialised|registry|store" | sed 's/^/  /' || true

# 6) pull this account's managed deps down over curl, then self-register mvpkg.
#    The bundled cut-down cmd/json bootstrap MVPKG; now that its HTTP seam works
#    (HTTPGETFILE shells out to curl), fetch the full published packages so they
#    show in MVPKG LIST and upgrade independently, and register mvpkg itself so
#    it is listed + upgradable (MVPKG update).  Best-effort: the bundled versions
#    already work, so a briefly-unreachable registry is a warning, not a failure.
say "pulling managed deps (json, cmd, curl-cmd) + registering mvpkg over curl  [needs network]"
# this release's own version (PKG line 2) — released layout has PKG beside
# install.sh, the dev tree has it one up — so register records what is actually
# installed, not whatever the registry currently calls latest.
MVVER="$(sed -n 2p "$HERE/PKG" 2>/dev/null || true)"; [ -n "$MVVER" ] || MVVER="$(sed -n 2p "$HERE/../PKG" 2>/dev/null || true)"
( cd "$HERE" && printf 'MVPKG install mvx-lang/json\nMVPKG install mvx-lang/cmd\nMVPKG install curl\nMVPKG register mvx-lang/mvpkg %s\nQUIT\n' "$MVVER" \
    | LANG="$LANG_OK" TERM=dumb "$UDT" ) 2>&1 \
  | grep -iE "install|deploy|registered|up to date|error|not found|refus" | sed 's/^/  /' || true

cat <<EOF
mvpkg-install: done.
  * operator account:   $HERE   (type MVPKG here)
  * CallC aggregator:   $UDTHOME/bin/udt-callc-build
Next, in this account:  MVPKG install <name>   |   MVPKG register mvx-lang/git
EOF
