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

# VOC is a directory file, but no VOC record is TRACKED any more -- VERBS
# declares the verbs and their records are derived (#45) -- and git does not
# keep an empty directory.  So a fresh checkout has no VOC at all.  CATALOG
# compiles first and opens VOC second, so without this every program still
# lands in CATALOG/, CATALOG prints "cannot open VOC" and STOPs with status 0,
# and the build reports success having registered no verb (#150).
mkdir -p "$HERE/VOC"

# BP/ plus any bundled source dir beside it.  There is none: mvpkg used to
# carry a cut-down cmd under cmd's OWN names, which collided with the real cmd
# package in a shared account and made which copy ran a matter of readdir order
# (#158).  cmd is a required dependency now and the installer fetches it.  The
# *.BP glob stays because mkpkg.sh compiles the same BP + *.BP set for any
# package that does bundle sources.
for f in BP $(cd "$HERE" && ls -d *.BP 2>/dev/null); do
  for it in $(cd "$HERE/$f" && ls); do
    MVXPRIV=developer "$MVX" -a "$HERE" -c "CATALOG $f $it"
  done
done

# EVERY SOURCE MUST HAVE COMPILED.  CATALOG reports a failed compile and STOPs
# with status 0 as well, so without this a source that did not compile simply
# goes missing from the package: 1.24.1 shipped without MVPKG.META, .ONE,
# .SEARCH and .TRACK -- install, info and search -- and the build said nothing
# (#154).  Each source is a verb (CATALOG/<name>) or a subroutine (LIB/<name>).
case "$(uname)" in Darwin) LIBSFX=dylib ;; *) LIBSFX=so ;; esac
missing=""
for f in BP $(cd "$HERE" && ls -d *.BP 2>/dev/null); do
  for it in $(cd "$HERE/$f" && ls); do
    case "$it" in *.H) continue ;; esac
    [ -e "$HERE/CATALOG/$it" ] || [ -e "$HERE/LIB/$it.$LIBSFX" ] || missing="$missing $f/$it"
  done
done
if [ -n "$missing" ]; then
  echo "build.sh: these sources did not compile:$missing" >&2
  echo "  (CATALOG's own messages above say why)" >&2
  exit 1
fi

# CATALOG cannot fail loudly (see above), so check the outcome it was for:
# every verb VERBS declares has a V record, pointing at a program that exists.
# A build that registers nothing must not look like one that worked.
if [ -f "$HERE/VERBS" ]; then
  while IFS= read -r vname || [ -n "$vname" ]; do
    case "$vname" in ''|'#'*) continue ;; esac
    rec="$HERE/VOC/$vname"
    if [ ! -x "$HERE/CATALOG/$vname" ]; then
      echo "build.sh: VERBS names $vname but CATALOG/$vname was not built" >&2; exit 1
    fi
    if [ ! -f "$rec" ] || [ "$(sed -n 1p "$rec")" != V ] \
       || [ "$(sed -n 2p "$rec")" != "CATALOG/$vname" ]; then
      echo "build.sh: VERBS names $vname but VOC/$vname is not a V record for CATALOG/$vname" >&2
      exit 1
    fi
  done < "$HERE/VERBS"
fi

# Bless the cataloged MVPKG binary in the SYSTEM account so its vendor permit
# (`permit prog:MVPKG = mkdir rmtree untar mkpkg chown` in .mvx) binds at the
# RESTRICTED tier: a prog: grant matches only the one file the system layer has
# whitelisted by sha256 — a self-blessing account cannot forge it.  The hash
# changes on every re-catalog, so re-bless here each build.  System-layer writes
# are an admin act; in a source checkout the build/system account is writable, in
# a deployment the installer runs this as the admin.  Set $MVXSYSTEM to override.
#
# ASK THE RUNTIME WHICH FILE THAT IS (mvx#373); do not hash CATALOG/MVPKG.  A
# cataloged program is TWO files on Linux, because glibc refuses to dlopen a PIE
# (mvx#203): CATALOG/MVPKG.so holds the code, and CATALOG/MVPKG is a byte-for-byte
# copy of mvx-launch -- the same bytes for every cataloged program on the machine.
# Hashing it blessed nothing in particular, and `mvx --program-hash' is the
# runtime answering for itself, by the same code that will do the comparing, so
# the two cannot drift.  On macOS the two files are one and the answers agree,
# which is why hashing the wrong one went unnoticed in development (#182).
SYS="${MVXSYSTEM:-${MVX_HOME:+$MVX_HOME/build/system}}"
BIN="$HERE/CATALOG/MVPKG"
if [ -n "$SYS" ] && [ -d "$SYS" ] && [ -f "$BIN" ]; then
  H="$("$MVX" --program-hash "$BIN" 2>/dev/null || true)"
  # ACCEPT ONLY AN ANSWER THAT LOOKS LIKE ONE.  An mvx without the flag prints
  # its usage and fails, and older still may print nothing; either way the
  # result is not 64 hex characters.  There is deliberately NO sha256sum
  # fallback: it is the bug above, and on an mvx that old a prog: grant bound to
  # nothing anyway (mvx#373), so a blessing that looks like it worked would be
  # worse than saying plainly that it did not.
  if [ "${#H}" -ne 64 ] || [ -n "$(printf '%s' "$H" | tr -d '0-9a-f')" ]; then
    echo "NOTE: this mvx cannot say which file holds a program (needs --program-hash," >&2
    echo "      mvx 0.9.0 or newer) — MVPKG not blessed; it will need the" >&2
    echo "      unrestricted tier until blessed by a newer mvx." >&2
    H=""
  fi
fi
if [ -n "${H:-}" ]; then
  mkdir -p "$SYS/.mvx-private"
  PROGS="$SYS/.mvx-private/programs"
  TMP="$PROGS.tmp.$$"
  { [ -f "$PROGS" ] && grep -v '^program MVPKG =' "$PROGS"; echo "program MVPKG = $H"; } \
    > "$TMP" 2>/dev/null && mv "$TMP" "$PROGS"
  echo "blessed MVPKG in $PROGS"
elif [ -z "$SYS" ] || [ ! -d "$SYS" ] || [ ! -f "$BIN" ]; then
  echo "NOTE: system account not found (set \$MVXSYSTEM) — MVPKG not blessed;" >&2
  echo "      it will need the unrestricted tier until blessed." >&2
fi

# SAY WHICH OF THE TWO HAPPENED.  Announcing the restricted tier after declining
# to bless is how a build reports a working permit it has not got: the first
# thing anyone does about the refusal that follows is reach for the unrestricted
# tier, and then the gate is decorative.
if [ -n "${H:-}" ]; then
  echo "mv_package built and blessed.  MVPKG runs at the RESTRICTED tier:"
else
  echo "mv_package built, NOT blessed.  MVPKG needs the UNRESTRICTED tier:"
fi
echo "  '$MVX' -a '$HERE' -c 'MVPKG install <name>'"
echo "(building a SOURCE package still needs the developer tier — BUILD-PKG compiles.)"
