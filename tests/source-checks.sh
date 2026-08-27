#!/usr/bin/env bash
# mvpkg — source-level checks.  Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only.
#
# These need no MV system at all: they read the sources and assert properties
# that must hold on every platform.  Every one of them exists because the thing
# it checks actually broke, and broke SILENTLY -- each of these bugs compiled
# cleanly on at least one system and failed at run time on another, which is why
# a compile is not the test.
#
#   sh tests/source-checks.sh [repo-root]
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n       %s\n' "$1" "$2"; }

# Every BASIC source in the client.  BP first, then the per-platform overrides.
SRC=$(ls BP/* udt/* CMD.BP/* 2>/dev/null | grep -vE '\.sh$|\.H$|README|/\._')

say() { printf '\n%s\n' "$*"; }

# --- 1. the shell is reached in exactly one place ---------------------------
# MVPKGOS was meant to be the only thing touching the OS and was not: five other
# programs shelled out directly, so a platform without `!` had to be fixed in
# six places instead of one.
say "the OS seam"
leaks=""
for f in $SRC; do
  case "$f" in */MVPKG.SH) continue;; esac
  grep -vE '^\s*\*' "$f" | grep -qE "EXECUTE +['\"]!" && leaks="$leaks $f"
done
if [ -z "$leaks" ]; then
  ok "the '!' shell escape appears only in MVPKG.SH"
else
  bad "the '!' shell escape appears only in MVPKG.SH" "also in: $(echo $leaks | tr '\n' ' ')"
fi

# --- 2. a $IFDEF needs something to have defined the symbol -----------------
# A $IFDEF on a symbol the source never included is silently FALSE, so the guard
# quietly takes its other arm.  This has now cost two repositories.
say "platform guards"
missing=""
for f in $SRC; do
  # MVX / ENGINE are builtin compiler defines; PLATFORM.H supplies the rest,
  # and a guard on one of THOSE without the include is silently false.
  grep -E '^[[:space:]]*\$IFDEF' "$f" \
    | grep -qvE '^[[:space:]]*\$IFDEF[[:space:]]+(MVX|ENGINE)[[:space:]]*$' || continue
  grep -qE '^[[:space:]]*\$INCLUDE[[:space:]]+MVPKG\.INC[[:space:]]+PLATFORM\.H' "$f" \
    || missing="$missing $f"
done
if [ -z "$missing" ]; then
  ok "every source using \$IFDEF includes PLATFORM.H"
else
  bad "every source using \$IFDEF includes PLATFORM.H" "missing in:$missing"
fi

# --- 3. the include must come AFTER the declaration -------------------------
say "include placement"
early=""
for f in $SRC; do
  n_inc=$(grep -nE '^\s*\$INCLUDE\s+MVPKG\.INC\s+PLATFORM\.H' "$f" | head -1 | cut -d: -f1)
  [ -n "$n_inc" ] || continue
  n_sub=$(grep -nE '^\s*(SUBROUTINE|PROGRAM|FUNCTION)\b' "$f" | head -1 | cut -d: -f1)
  [ -n "$n_sub" ] || continue
  [ "$n_inc" -gt "$n_sub" ] || early="$early $f"
done
if [ -z "$early" ]; then
  ok "PLATFORM.H is included after SUBROUTINE/PROGRAM, never before"
else
  bad "PLATFORM.H is included after SUBROUTINE/PROGRAM" "before it in:$early"
fi

# --- 4. no valued $DEFINE inside a guard ------------------------------------
# On jBASE a $DEFINE inside a FALSE $IFDEF still takes effect.  A guarded rename
# therefore leaks and rewrites calls on the platform it was guarded away from.
say "preprocessor"
guarded=""
for f in $SRC; do
  # depth-tracking with awk; the $ in $IFDEF is escaped so awk does not read it
  # as a field reference, which is what silently disabled this check once.
  if awk 'BEGIN{d=0}
          /^[[:space:]]*[$]IFDEF/{d=1; next}
          /^[[:space:]]*[$]ENDIF/{d=0; next}
          d && /^[[:space:]]*[$]DEFINE[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]/{found=1}
          END{exit !found}' "$f"; then
    guarded="$guarded $f"
  fi
done
if [ -z "$guarded" ]; then
  ok "no valued \$DEFINE inside a \$IFDEF (it leaks on jBASE)"
else
  bad "no valued \$DEFINE inside a \$IFDEF" "found in:$guarded"
fi

# --- 5. $IFDEF takes ONE symbol ---------------------------------------------
# UniData rejects `$IFDEF A || B`; jBASE and MVX accept it and silently use only
# the first symbol, so it appears to work depending on the order written.
multi=$(grep -nE '^[[:space:]]*[$]IFDEF[[:space:]]+[^[:space:]]+[[:space:]]+([|][|]|OR|&&|AND)' \
          $SRC 2>/dev/null || true)
if [ -z "$multi" ]; then
  ok "no \$IFDEF combines symbols (no system supports it)"
else
  bad "no \$IFDEF combines symbols" "$multi"
fi

# --- 6. the master dictionary is named once ---------------------------------
# jBASE has MD, everyone else has VOC.  PLATFORM.H says which; nothing else
# should hardcode it.
say "portability"
voc=$(grep -nE 'OPEN\s+"VOC"' $SRC 2>/dev/null || true)
if [ -z "$voc" ]; then
  ok 'no source hardcodes OPEN "VOC" (use MVMASTER)'
else
  bad 'no source hardcodes OPEN "VOC"' "$voc"
fi

# --- 7. jBASE reserved words are not used as identifiers --------------------
# Each of these is a function or keyword on jBASE, so using it as a variable or
# a parameter is a syntax error there and fine everywhere else.
resv="OUT SUB SENTENCE STATUS KEY DIR COUNT DATA LN NEG"
hits=""
for w in $resv; do
  h=$(grep -nE "(SUBROUTINE[^(]*\([^)]*[^A-Z0-9.]$w[,)]|^[[:space:]]*$w[[:space:]]*=)" \
        $SRC 2>/dev/null | grep -vE '^[^:]*:[0-9]*:[[:space:]]*[*]' | head -3 || true)
  [ -n "$h" ] && hits="$hits
$w: $h"
done
if [ -z "$hits" ]; then
  ok "no jBASE reserved word used as a variable or parameter"
else
  bad "no jBASE reserved word used as a variable or parameter" "$hits"
fi

# --- 8. LOCATE Format 1 only ------------------------------------------------
loc=""
for f in $SRC; do
  h=$(grep -nvE '^\s*\*' "$f" | grep -E '\bLOCATE\s+[^(]' | grep -viE 'locate\(' || true)
  [ -n "$h" ] && loc="$loc
$f: $h"
done
if [ -z "$loc" ]; then
  ok "LOCATE is always the parenthesised Format 1"
else
  bad "LOCATE is always the parenthesised Format 1" "$loc"
fi

# --- 9. no DEFFUN ... CALLING (U2 only) -------------------------------------
cal=$(grep -nE 'DEFFUN.*\bCALLING\b' $SRC 2>/dev/null | grep -v '^\S*:[0-9]*:\s*\*' || true)
if [ -z "$cal" ]; then
  ok "no unguarded DEFFUN ... CALLING (jBASE has no CALLING clause)"
else
  # it is allowed, but only behind a guard
  ungu=""
  for f in $(echo "$cal" | cut -d: -f1 | sort -u); do
    grep -qE '^\s*\$IFDEF' "$f" || ungu="$ungu $f"
  done
  if [ -z "$ungu" ]; then ok "DEFFUN ... CALLING only appears behind a platform guard"
  else bad "DEFFUN ... CALLING only behind a guard" "unguarded in:$ungu"; fi
fi

printf '\n%s\n' "source-checks: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
