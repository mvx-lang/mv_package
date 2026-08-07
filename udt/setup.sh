#!/bin/sh
# mv_package — one-time UniData setup.  Copyright (C) 2026 Gordon Heydon.
# GPL-2.0-only.
#
# Installs the two host-level pieces the package manager needs on UniData:
#   1. the shared-library aggregator (udt-callc-build), which rebuilds
#      libu2callc.so from every installed package's native contribution;
#   2. the core capability probe CALLC.EXISTS, cataloged GLOBALLY so that
#      EVERY account can ask "is this native add-on installed?" WITHOUT the
#      add-on — or any particular package — being present.  This is what
#      lets a program use e.g. udt_curses when it is there and fall back
#      cleanly when it is not, checking without installing.
#
# Run once per UniData host.  Needs a UniData account to compile from
# (defaults to the current directory) and rights to write $UDTHOME.
set -e

: "${UDTHOME:?set UDTHOME to your UniData home (e.g. /usr/ud83)}"
SUDO=${SUDO-sudo}
HERE=$(cd "$(dirname "$0")" && pwd)
ACCT=${1:-$(pwd)}          # a UniData account (has a BP file) to compile from

# 1) the shared-library aggregator, at the path udt/MVPKGOS drives
$SUDO cp "$HERE/udt-callc-build.sh" "$UDTHOME/bin/udt-callc-build"
$SUDO chmod +x "$UDTHOME/bin/udt-callc-build"
echo "mv_package: installed $UDTHOME/bin/udt-callc-build"

# 2) the capability + package probes, cataloged globally so every account can
#    guard optional add-ons at run time: CALLC.EXISTS (a native CallC function
#    is present) and MVPKG.HAS (a "?"-optional package is installed here).
mkdir -p "$ACCT/BP"
for probe in CALLC.EXISTS MVPKG.HAS; do
   cp "$HERE/$probe" "$ACCT/BP/$probe"
   ( cd "$ACCT" && printf 'BASIC BP %s\nCATALOG BP %s FORCE\n' "$probe" "$probe" | udt ) >/dev/null 2>&1
done
echo "mv_package: cataloged CALLC.EXISTS + MVPKG.HAS globally — every account can"
echo "mv_package:   now guard optional add-ons at run time, e.g."
echo "mv_package:     DEFFUN CALLC.EXISTS(A)"
echo "mv_package:     IF CALLC.EXISTS(\"CURSINIT\") THEN ... ELSE ..."
echo "mv_package:     CALL MVPKG.HAS(\"mvx-lang/udt_curses\", OK)"
