#!/bin/sh
# mvpkg — udt-callc-build refuses a fragment that declares without implementing.
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only.
#
# UniData loads exactly ONE libu2callc.so, built from the union of every staged
# fragment.  So a fragment listing functions in `funcs` with no *.c or *.o to
# define them does not merely fail to add itself — relinking drops those symbols
# for every account that had them, and the failure lands far away as
# `undefined symbol: <NAME>` (mv_package#143).
#
# A source tarball is precisely that shape: compiled CallC objects are build
# output and gitignored, so `udt-callc/` arrives as funcs + libs and nothing
# else.  Installing a source release of mvx-lang/git this way stripped the GIT
# verb's 39 functions out of a working library, and the install reported success.
#
# Drives the real script against a fake UDTHOME; the guards fire long before any
# UniData generator is needed.
#
# Honest limit: the two "the library was never relinked" assertions cannot fail
# on a host without gencdef/genefs/genfunc — an unguarded run dies at the first
# generator (127) before it reaches the link, so they pass either way here.  They
# bite only where the generators exist (a self-hosted udt runner, or a real box).
# Every other assertion below distinguishes guarded from unguarded on any host;
# run against the pre-guard script, 8 of them go red.
#
#   sh tests/callc-guard.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/udt/udt-callc-build.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (expected [$2], got [$1])"; fi; }

# a throwaway UDTHOME: callc.d for staging, bin/work for the generator inputs
UDTHOME="$WORK/ud"; CALLCD="$WORK/callc.d"
mkdir -p "$UDTHOME/bin/work" "$CALLCD"
: > "$UDTHOME/bin/work/efsdef"; : > "$UDTHOME/bin/work/libuvic.a"
LIB="$UDTHOME/bin/libu2callc.so"; echo "ORIGINAL-LIBRARY" > "$LIB"

run() { # run <pkgdir> <name> -> prints exit code, output to $WORK/out
  ( UDTHOME="$UDTHOME" UDT_CALLCD="$CALLCD" SUDO= sh "$BUILD" add "$1" "$2" ) \
    > "$WORK/out" 2>&1
  echo $?
}

mkfrag() { # mkfrag <dir> <n-declarations> [file...]
  d="$1/udt-callc"; rm -rf "$1"; mkdir -p "$d"
  n=$2; shift 2
  : > "$d/funcs"
  i=0; while [ "$i" -lt "$n" ]; do echo "FN$i:string:1:string" >> "$d/funcs"; i=$((i+1)); done
  echo '-lgit2' > "$d/libs"
  for f in "$@"; do : > "$d/$f"; done
}

printf 'callc-guard: the refusal\n'

# A good fragment is staged first, so we can prove a later refusal does not
# disturb it — the whole point of checking before the staging dir is wiped.
mkfrag "$WORK/good" 3 impl.o
rc=$(run "$WORK/good" scope/good)
grep -q 'staged scope_good' "$WORK/out" \
  && ok 'a fragment shipping an object is staged' \
  || bad "a fragment shipping an object is staged ($(head -2 "$WORK/out" | tr '\n' ' '))"
[ -f "$CALLCD/scope_good/impl.o" ] && ok 'its object reached callc.d' || bad 'its object reached callc.d'

# The regression: declarations, no code.  This is a source tarball.
mkfrag "$WORK/bare" 42
rc=$(run "$WORK/bare" scope/bare)
check "$rc" 4 'a funcs-only fragment is refused (exit 4)'
grep -q 'refusing to stage scope/bare' "$WORK/out" \
  && ok 'and says which package, by its real name' || bad 'and says which package, by its real name'
grep -q '42 CallC function' "$WORK/out" \
  && ok 'and how many declarations it could not honour' || bad 'and how many declarations it could not honour'
grep -q 'binary artifact' "$WORK/out" \
  && ok 'and what to do instead' || bad 'and what to do instead'
[ ! -d "$CALLCD/scope_bare" ] && ok 'nothing was staged for it' || bad 'nothing was staged for it'
[ -f "$CALLCD/scope_good/impl.o" ] \
  && ok 'the previously staged package is untouched' \
  || bad 'the previously staged package is untouched — the refusal broke a working box'
[ "$(cat "$LIB")" = "ORIGINAL-LIBRARY" ] \
  && ok 'and the live library was never relinked' || bad 'and the live library was never relinked'

printf 'callc-guard: what must still be allowed\n'

# Sources instead of objects: the other legitimate shape.
mkfrag "$WORK/src" 2 impl.c
rc=$(run "$WORK/src" scope/src)
grep -q 'staged scope_src' "$WORK/out" \
  && ok 'a fragment shipping C sources is staged' || bad 'a fragment shipping C sources is staged'

# No declarations at all is not this bug — nothing is promised, nothing is lost.
mkfrag "$WORK/empty" 0
rc=$(run "$WORK/empty" scope/empty)
grep -q 'staged scope_empty' "$WORK/out" \
  && ok 'an empty funcs is not refused' || bad 'an empty funcs is not refused'

# A package with no udt-callc/ at all is an ordinary non-native install.
rm -rf "$WORK/none"; mkdir -p "$WORK/none"
rc=$(run "$WORK/none" scope/none)
check "$rc" 0 'a package with no udt-callc/ still exits 0'

printf 'callc-guard: an already-staged fragment (a bare rebuild)\n'

# Reached without going through `add`: a box staged before this guard existed,
# or a hand-edited callc.d.  Refusing must KEEP the working library.
mkdir -p "$CALLCD/scope_stale"
printf 'AGOPEN:string:1:string\n' > "$CALLCD/scope_stale/funcs"
( UDTHOME="$UDTHOME" UDT_CALLCD="$CALLCD" SUDO= sh "$BUILD" ) > "$WORK/out" 2>&1
rc=$?
check "$rc" 4 'a bare rebuild refuses the stale fragment'
grep -q 'Keeping the current library' "$WORK/out" \
  && ok 'and says the library was kept' || bad 'and says the library was kept'
grep -q 'remove scope_stale' "$WORK/out" \
  && ok 'and offers the escape hatch' || bad 'and offers the escape hatch'
[ "$(cat "$LIB")" = "ORIGINAL-LIBRARY" ] \
  && ok 'the library really is untouched' || bad 'the library really is untouched'

printf '\ncallc-guard: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
