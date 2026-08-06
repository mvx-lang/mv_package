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
: "${MVX_HOME:?set MVX_HOME to your mvx-lang checkout (with a built toolchain)}"
MVX="$MVX_HOME/build/bin/mvx"
[ -x "$MVX" ] || { echo "mvx not found under $MVX_HOME/build/bin" >&2; exit 1; }
export MVX_DRIVERS="$MVX_HOME/build/lib"

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
