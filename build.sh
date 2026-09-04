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
# derived).  This also blesses the MVPKG binary in the system account so it runs
# CONFINED at the restricted tier (see below).  Then, e.g.:
#   mvx -a . -c 'MVPKG install ev_eb ./ev_eb'
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
# MVPKG.INC/PLATFORM.H — the per-platform facts the sources $INCLUDE.  Kept
# byte-for-byte identical to what MVPKGOS INCSETUP writes, so `MVPKG init` does
# not quietly rewrite the file the account was compiled against.  Written
# HERE, before the first compile, because several BP records include it and a
# missing include is a hard compile error.  MVPKGOS INCSETUP writes the same
# file into MANAGED accounts at `MVPKG init`; this is the one for the client's
# own account, which is compiled before any init has run.
#
# Two facts, both of which were previously $IFDEF'd at every call site:
#   MVMASTER  the account's master dictionary — VOC here, MD on jBASE.
#   GETENV    MVX spells the environment ENV(); everyone else spells it GETENV.
mkdir -p "$HERE/MVPKG.INC"
cat > "$HERE/MVPKG.INC/PLATFORM.H" <<'PLATEOF'
* PLATFORM.H - platform compile-time defines.
* MVX is a builtin compiler define; nothing to declare here.
EQUATE MVMASTER TO "VOC"
$DEFINE GETENV ENV
PLATEOF
echo "wrote MVPKG.INC/PLATFORM.H (MVMASTER=VOC, GETENV=ENV)"

for it in $(cd "$HERE/BP" && ls); do
  MVXPRIV=developer "$MVX" -a "$HERE" -c "CATALOG BP $it"
done

# Bless the cataloged MVPKG binary in the SYSTEM account so its vendor permit
# (`permit prog:MVPKG = mkdir rmtree untar mkpkg chown` in .mvx) binds at the
# RESTRICTED tier: a prog: grant matches only the exact binary the system layer
# has whitelisted by sha256 — a self-blessing account cannot forge it.  The hash
# changes on every re-catalog, so re-bless here each build.  System-layer writes
# are an admin act; in a source checkout the build/system account is writable, in
# a deployment the installer runs this as the admin.  Set $MVXSYSTEM to override.
SYS="${MVXSYSTEM:-${MVX_HOME:+$MVX_HOME/build/system}}"
BIN="$HERE/CATALOG/MVPKG"
if [ -n "$SYS" ] && [ -d "$SYS" ] && [ -f "$BIN" ]; then
  if command -v sha256sum >/dev/null 2>&1; then H="$(sha256sum "$BIN" | cut -d' ' -f1)"
  else H="$(shasum -a 256 "$BIN" | cut -d' ' -f1)"; fi
  mkdir -p "$SYS/.mvx-private"
  PROGS="$SYS/.mvx-private/programs"
  TMP="$PROGS.tmp.$$"
  { [ -f "$PROGS" ] && grep -v '^program MVPKG =' "$PROGS"; echo "program MVPKG = $H"; } \
    > "$TMP" 2>/dev/null && mv "$TMP" "$PROGS"
  echo "blessed MVPKG in $PROGS"
else
  echo "NOTE: system account not found (set \$MVXSYSTEM) — MVPKG not blessed;" >&2
  echo "      it will need the unrestricted tier until blessed." >&2
fi

echo "mv_package built and blessed.  MVPKG runs at the RESTRICTED tier:"
echo "  '$MVX' -a '$HERE' -c 'MVPKG install <name>'"
echo "(building a SOURCE package still needs the developer tier — BUILD-PKG compiles.)"
