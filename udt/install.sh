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
# The operator: an explicit UDT_OWNER, else whoever owns this unpacked release
# (they unpacked it as themselves).  Robust whether we were started with sudo, su,
# or a plain root login — unlike $SUDO_USER, which is unset under `su -`/a root
# shell.  Fall back to the current user only if the dir owner is unreadable/root.
OWNER="${UDT_OWNER:-$(ls -ld "$HERE" 2>/dev/null | awk 'NR==1{print $3}')}"
[ -n "$OWNER" ] && [ "$OWNER" != root ] || OWNER="$(id -un)"
GROUP="${UDT_GROUP:-$(id -gn "$OWNER" 2>/dev/null || echo "$OWNER")}"
UDT="$UDTHOME/bin/udt"

say() { printf 'mvpkg-install: %s\n' "$1"; }
die() { printf 'mvpkg-install: %s\n' "$1" >&2; exit 1; }
[ -d "$UDTHOME" ] && [ -x "$UDT" ] || die "UDTHOME=$UDTHOME is not a UniData install (set UDTHOME)"
command -v sudo >/dev/null 2>&1 || die "sudo not found — needed for \$UDTHOME writes"
# MVPKG fetches packages over HTTP through the curl seam (UniData's native HTTPS
# doesn't reliably reach github + follow redirects), so curl is a prerequisite.
command -v curl >/dev/null 2>&1 || die "curl not found — MVPKG downloads packages over HTTP with curl: sudo dnf install -y curl"
[ -d "$HERE/BP" ] || die "no BP/ here — run this from the unpacked mvpkg udt account"

# Do the operator-level work (newacct, the GLOBAL catalog, MVPKG init + the store)
# AS THE OPERATOR, not root: root is needed only for the $UDTHOME/bin writes, which
# the steps below elevate with sudo themselves.  This matters because a native
# `MVPKG install` catalogs GLOBALLY as the operator, and a later `MVPKG update`
# re-catalogs the same way — if install left the CTLG entries root-owned, that
# update fails with 'Copy catalog file error'.  So if we are root ("am I root" is
# `id -u`, NOT $SUDO_USER) but the operator is someone else, re-exec as them; the
# operator's sudo then elevates only the few $UDTHOME writes (the same it would if
# invoked as `./install.sh` directly — no new requirement).
if [ "$(id -u)" = 0 ] && [ "$OWNER" != root ]; then
  id "$OWNER" >/dev/null 2>&1 || die "operator '$OWNER' is not a user — set UDT_OWNER"
  say "root invocation: re-running as the operator '$OWNER' (root elevates only \$UDTHOME writes)"
  exec sudo -u "$OWNER" UDTHOME="$UDTHOME" LANG="$LANG_OK" MVPKG_STORE="${MVPKG_STORE:-}" \
    UDT_OWNER="$OWNER" UDT_GROUP="$GROUP" -- "$HERE/$(basename -- "$0")" "$@"
fi

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
GLOBAL="MVPKGOS MVPKGDEP MVPKG.HTTPGET MVPKG.HTTPGETFILE MVPKG.JSONDECODE MVPKG.MAPFIELD SEMVER \
CMD.INIT CMD.ADD CMD.RUN MVPKG.REG MVPKG.META MVPKG.ONE \
MVPKG.INSTALL MVPKG.INFO MVPKG.LIST MVPKG.UPDATE MVPKG.REMOVE \
MVPKG.REGISTER MVPKG.SEARCH MVPKG.SETUP MVPKG.CONFIG MVPKG.REBUILD MVPKG.INIT \
MVPKG.NOTIFY"

# Auto-repair: an earlier `sudo ./install.sh` (before the installer re-execed as
# the operator) may have left this account or our GLOBAL catalog entries
# root-owned — a re-catalog below would then fail with 'Copy catalog file error'.
# We run as the operator now (post re-exec) but still have sudo, so hand any such
# stragglers to the operator first.  A fresh install is a harmless no-op.  This is
# the install-time half of `MVPKG fixperms`; the store + callc.d are re-owned by
# their own steps (below / udt-callc-build).
sudo chown -R "$OWNER:$GROUP" "$HERE" 2>/dev/null || true
for v in $PROBES $GLOBAL; do
  sudo chown "$OWNER:$GROUP" "$UDTHOME"/sys/CTLG/*/"$v" 2>/dev/null || true
done

say "compiling + cataloging the client (globals + probes) and the MVPKG verb"
# One BASIC per program, not one BASIC with a long arg list: `BASIC BP <many
# args>` segfaults udt on this UniData (it still writes the objects, but the
# session dies before the CATALOGs run).  Per-program compile is clean.
{
  for p in $PROBES $GLOBAL MVPKG MVPKG.FIXPERMS; do echo "BASIC BP $p"; done
  for p in $PROBES $GLOBAL; do echo "CATALOG BP $p FORCE"; done
  # MVPKG + fixperms are LOCAL to this operator account: fixperms is a host-admin
  # task (chowns the DBA-owned catalog, reassigns the operator) and must not be
  # reachable from accounts a package was merely deployed into.
  echo "CATALOG BP MVPKG LOCAL FORCE"
  echo "CATALOG BP MVPKG.FIXPERMS LOCAL FORCE"
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
( cd "$HERE" && printf 'MVPKG init -y\nQUIT\n' | LANG="$LANG_OK" TERM=dumb "$UDT" ) 2>&1 \
  | grep -iE "initialised|registry|store|include" | sed 's/^/  /' || true

# 6) pull this account's managed deps down over curl, then self-register mvpkg.
#    The bundled cut-down cmd/json bootstrap MVPKG; now that its HTTP seam works
#    (HTTPGETFILE shells out to curl), fetch the full published packages so they
#    show in MVPKG LIST and upgrade independently, and register mvpkg itself so
#    it is listed + upgradable (MVPKG update).  Best-effort: the bundled versions
#    already work, so a briefly-unreachable registry is a warning, not a failure.
# Choose the HTTP transport.  Both mvx-lang/curl-cmd (shells out to the OS curl
# binary) and mvx-lang/curl (in-process libcurl via CallC — faster, no fork per
# request) provide the virtual "curl", so either satisfies mvpkg's dependency.
# Prefer libcurl when its build requirements are present — gcc, the OS libcurl,
# and the ncurses the UniData CallC link pulls — probed by actually trying that
# link; otherwise use the portable command version.
if command -v gcc >/dev/null 2>&1 \
   && printf 'int main(void){return 0;}\n' | gcc -xc - -l:libcurl.so.4 -lncurses -o /dev/null 2>/dev/null; then
  HTTPPKG="mvx-lang/curl";     HTTPWHICH="in-process libcurl (mvx-lang/curl)"
else
  HTTPPKG="mvx-lang/curl-cmd"; HTTPWHICH="OS curl command (mvx-lang/curl-cmd)"
fi
say "HTTP transport: $HTTPWHICH"
say "pulling managed deps (json, cmd, ${HTTPPKG#mvx-lang/}) + registering mvpkg over curl  [needs network]"
# this release's own version (PKG line 2) — released layout has PKG beside
# install.sh, the dev tree has it one up — so register records what is actually
# installed, not whatever the registry currently calls latest.
MVVER="$(sed -n 2p "$HERE/PKG" 2>/dev/null || true)"; [ -n "$MVVER" ] || MVVER="$(sed -n 2p "$HERE/../PKG" 2>/dev/null || true)"
# ONE MVPKG command per udt session.  Each `MVPKG install` spawns child udt
# processes (compile + catalog) that talk over SysV message queues; running
# several commands back-to-back in a single piped session intermittently fails
# with "can't get to msgq in U_tosbcs" as those queues contend.  Per-session is
# the same one-op-per-session rule the global catalog above already follows.
for dep in mvx-lang/json mvx-lang/cmd "$HTTPPKG"; do
  ( cd "$HERE" && printf 'MVPKG install %s\nQUIT\n' "$dep" | LANG="$LANG_OK" TERM=dumb "$UDT" ) 2>&1 \
    | grep -iE "installed |deploy|up to date|error|not found|refus|msgq" | sed 's/^/  /' || true
done
( cd "$HERE" && printf 'MVPKG register mvx-lang/mvpkg %s\nQUIT\n' "$MVVER" | LANG="$LANG_OK" TERM=dumb "$UDT" ) 2>&1 \
  | grep -iE "registered|error|not found|msgq" | sed 's/^/  /' || true

# Safety net: the re-exec above means the operator work already ran as $OWNER, so
# the account, catalog and store are operator-owned.  But a $UDTHOME write elevated
# with sudo, or a pre-existing store dir from an earlier root install, could still
# leave a root-owned file the operator's MVPKG must later overwrite — so reassert
# operator ownership of the account + store (a no-op when it already holds).  This
# only covers $HERE/$STORE; global catalog ownership comes from cataloging as the
# operator, which the re-exec guarantees (a chown of $UDTHOME/sys/CTLG would fight
# UniData's own catalog bookkeeping).
sudo chown -R "$OWNER:$GROUP" "$HERE" "$STORE" 2>/dev/null || true

cat <<EOF
mvpkg-install: done.
  * operator account:   $HERE   (type MVPKG here)
  * HTTP transport:     $HTTPWHICH
  * CallC aggregator:   $UDTHOME/bin/udt-callc-build
Next, in this account:  MVPKG install <name>   |   MVPKG register mvx-lang/git
EOF

# Packages with native (CallC) code — git, curl, curses, ... — are compiled into
# UniData at install, which needs a C build toolchain.  The toolchain (and how to
# install it) differs by platform, so tailor the hint by OS + package manager and
# fall back to a generic note; only mention it when no compiler is on PATH.
# Pure-BASIC packages need none of this.
if ! command -v gcc >/dev/null 2>&1 && ! command -v cc >/dev/null 2>&1; then
  case "$(uname -s 2>/dev/null || echo unknown)" in
    Linux)
      if   command -v dnf     >/dev/null 2>&1; then TOOLHINT="sudo dnf install -y gcc ncurses-devel"
      elif command -v yum     >/dev/null 2>&1; then TOOLHINT="sudo yum install -y gcc ncurses-devel"
      elif command -v apt-get >/dev/null 2>&1; then TOOLHINT="sudo apt-get install -y gcc libncurses-dev"
      else TOOLHINT="install gcc and the ncurses development files with your package manager"; fi ;;
    AIX)  TOOLHINT="install a C compiler (gcc from the AIX Toolbox, or IBM XL C) and the library development files" ;;
    *)    TOOLHINT="install your platform's C compiler and the development files for the libraries native packages link" ;;
  esac
  cat <<EOF

mvpkg-install: TIP — installing packages with native (CallC) code (git, curl,
  curses, ...) needs a C build toolchain.  On this system:
      $TOOLHINT
  Each native package also names the OS C library it links; MVPKG preflights it
  before building and tells you exactly what to install.
EOF
fi
