#!/bin/sh
# mv_package — build the MVX account: compile + catalog the MVPKG client.
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see LICENSE).
#
#   MVX_HOME=/path/to/mvx-lang ./build.sh
#
# The repository IS the MVX account: VOC and BP are directory files, so every
# record is a plain tracked file and there is nothing to import — the working
# tree is the live account.  Needs an mvx-lang checkout with a built toolchain
# (the http and json extension packages installed in its system account, which
# is the default MVX_PACKAGES).  Leaves CATALOG/ and LIB/ in place (git-ignored,
# derived).  Then, e.g.:
#   MVXPRIV=unrestricted mvx -a . -c 'MVPKG install ev_eb ./ev_eb'
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
# The mvx runtime + its drivers.  Default to a source checkout's build tree
# ($MVX_HOME/build/bin/mvx + build/lib), but allow $MVX / $MVX_DRIVERS overrides
# so a PUBLISHED toolchain works too (e.g. CI's setup-mvx puts mvx on PATH and
# ships the drivers under $MVXHOME/lib) — no full checkout required.
MVX="${MVX:-${MVX_HOME:+$MVX_HOME/build/bin/mvx}}"
[ -n "$MVX" ] && [ -x "$MVX" ] || MVX="$(command -v mvx 2>/dev/null || true)"
[ -n "$MVX" ] && [ -x "$MVX" ] || { echo "mvx not found — set \$MVX or MVX_HOME, or put mvx on PATH" >&2; exit 1; }
export MVX_DRIVERS="${MVX_DRIVERS:-${MVX_HOME:+$MVX_HOME/build/lib}}"
: "${MVX_DRIVERS:?set MVX_DRIVERS (or MVX_HOME) to the mvx driver dir}"

# Catalog every BP record (developer privilege to compile and catalog): the
# client verb MVPKG, the OS seam MVPKGOS, SEMVER, the presence probe MVPKG.HAS,
# and every MVPKG.* subroutine the verb CALLs — CALL does not cascade, so each
# must be cataloged for `MVPKG install` to resolve its whole chain.  CATALOG
# picks exe vs shared from each record's SUBROUTINE declaration.
for it in $(cd "$HERE/BP" && ls); do
  MVXPRIV=developer "$MVX" -a "$HERE" -c "CATALOG BP $it"
done
echo "mv_package built.  run (installing needs the unrestricted tier for untar):"
echo "  MVXPRIV=unrestricted '$MVX' -a '$HERE' -c 'MVPKG install ev_eb ./ev_eb'"
