#!/usr/bin/env bash
# mvpkg — does source-checks.sh actually check anything?
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only.
#
# A check that cannot fail is decoration, and decoration is worse than nothing
# because it reports success.  Four of the nine checks in source-checks.sh were
# exactly that when first written -- they used \s and \b, which BSD grep does
# not know, so the patterns never matched anything and every run was green.
#
# So each check is verified by BREAKING a throwaway copy of the tree in the
# specific way that check exists to catch, and asserting it goes red.
#
#   sh tests/self-check.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
M="$WORK/mutant"

reset() { rm -rf "$M"; cp -r "$ROOT" "$M"; rm -rf "$M/.git"; }
# The sources do NOT end in a newline, so an appended line would otherwise glue
# itself onto the last statement and the mutation would not be what it looks
# like.  This cost a full round of false "the check is broken" conclusions.
add()   { printf '\n%s\n' "$1" >> "$M/BP/MVPKG.INFO"; }
red()   { sh "$M/tests/source-checks.sh" "$M" 2>/dev/null | grep -c '^  FAIL'; }

probe() { # probe DESCRIPTION  (mutation already applied)
  if [ "$(red)" -gt 0 ]; then PASS=$((PASS+1)); printf '  ok   detects %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL does NOT detect %s — that check is decoration\n' "$1"; fi
  reset
}

reset
if [ "$(red)" -ne 0 ]; then
  printf '  FAIL the unmodified tree is not clean; fix that before trusting this\n'
  sh "$M/tests/source-checks.sh" "$M" | grep '^  FAIL'
  exit 1
fi
printf '  ok   the unmodified tree is clean\n'

add "   EXECUTE '!ls'";                      probe "a shell escape outside MVPKG.SH"
add '$IFDEF JBASE';                          probe "\$IFDEF on a PLATFORM.H symbol with no include"
add '$IFDEF AA || BB';                       probe "\$IFDEF combining two symbols"
add '   OUT = 1';                            probe "a jBASE reserved word as a variable"
add '   SUBROUTINE X(A, KEY, B)';            probe "a jBASE reserved word as a parameter"
add '   OPEN "VOC" TO F ELSE STOP';          probe "a hardcoded VOC open"
add '   LOCATE X IN Y SETTING P ELSE STOP';  probe "LOCATE Format 2"
printf '\n$IFDEF MVX\n$DEFINE FOO BAR\n$ENDIF\n' >> "$M/BP/MVPKG.INFO"
                                             probe "a valued \$DEFINE inside a guard"
sed -e '1i\
$INCLUDE MVPKG.INC PLATFORM.H
' "$M/BP/MVPKG.REG" > "$M/BP/MVPKG.REG.tmp" && mv "$M/BP/MVPKG.REG.tmp" "$M/BP/MVPKG.REG"
                                             probe "PLATFORM.H included before SUBROUTINE"

printf '\nself-check: %s checks proven able to fail, %s decoration\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
