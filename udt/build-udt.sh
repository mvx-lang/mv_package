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

# The client programs, probes, and cmd framework -> BP (each a plain record).
# MVPKG* covers MVPKG, MVPKG.*, MVPKGOS, MVPKGDEP, MVPKG.HAS.
cp "$HERE"/MVPKG* "$HERE"/SEMVER "$HERE"/HTTPGET "$HERE"/HTTPGETFILE \
   "$HERE"/JSONDECODE "$HERE"/MAPFIELD "$HERE"/CALLC.EXISTS "$ACCT/BP/"
cp "$HERE"/CMD.BP/CMD.INIT "$HERE"/CMD.BP/CMD.ADD "$HERE"/CMD.BP/CMD.RUN "$ACCT/BP/"

# The self-installer, the CallC aggregator it deploys, and the package metadata.
cp "$HERE"/install.sh          "$ACCT/install.sh";          chmod +x "$ACCT/install.sh"
cp "$HERE"/udt-callc-build.sh  "$ACCT/udt-callc-build.sh";  chmod +x "$ACCT/udt-callc-build.sh"
cp "$ROOT"/PKG "$ROOT"/mvpkg.json "$ROOT"/LICENSE "$ROOT"/README.md "$ACCT/" 2>/dev/null || true

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
