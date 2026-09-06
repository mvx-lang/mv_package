#!/bin/sh
# mv_package — run the portable BASIC unit tests.  GPL-2.0-only.
#
#   MVX_HOME=/path/to/mvx-lang tests/semver-tests.sh
#
# SEMVER IS PURE LOGIC AND DESERVES A TEST THAT IS NOT AN INSTALL.  Version
# ranges and stability floors decide which build every platform downloads, and
# the only way that was ever exercised was end-to-end against a live registry —
# where a wrong answer looks like a network problem.  These compile the real
# BP/SEMVER (no copy, no stub) against a driver and assert its answers.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
MVXB="${MVXB:-${MVX_HOME:+$MVX_HOME/build/bin/mvx-basic}}"
[ -n "$MVXB" ] && [ -x "$MVXB" ] || MVXB="$(command -v mvx-basic 2>/dev/null || true)"
[ -n "$MVXB" ] && [ -x "$MVXB" ] || { echo "mvx-basic not found — set \$MVXB or MVX_HOME" >&2; exit 2; }

WORK="$(mktemp -d /tmp/mvpkgtest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/BP/SEMVER" "$WORK/SEMVER.b"
# NOT "semver.b" — macOS is case-insensitive, so the driver would land on top of
# the SEMVER.b copied above and the link would then see two mvx_main.
cp "$HERE/semver-test.b" "$WORK/semver-test.b"
"$MVXB" -c "$WORK/SEMVER.b" -o "$WORK/SEMVER.o"
"$MVXB" "$WORK/semver-test.b" "$WORK/SEMVER.o" -o "$WORK/semver-test"
OUT="$("$WORK/semver-test")"
echo "$OUT"
case "$OUT" in
  *"ALL PASS") exit 0 ;;
  *) exit 1 ;;
esac
