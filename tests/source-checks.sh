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


# --- 10/11. the environment and OS files are reached through their seams ----
# UniVerse has NEITHER GETENV nor OSREAD/OSWRITE, and says so unhelpfully: it
# parses GETENV(x) as an undimensioned array and `OSREAD X FROM p` as a variable
# being assigned.  Both live behind one subroutine each so uv needs one arm, not
# sixty-two.
# --- a CALL must agree with its SUBROUTINE about how many arguments ---------
# MV BASIC does not check this at compile time.  The mismatch surfaces at RUN
# time, as SUBROUTINE_PARM_ERROR, on whichever path happens to reach the call --
# so it hides in the commands nobody exercised that day.  Adding a parameter to
# MVPKGDEP for mv_package#105 updated two of its five callers, and `remove`,
# `update` and `fixperms` shipped in 1.22.0 calling it with four arguments
# against a five-argument declaration.
#
# Argument counting is PAREN-AWARE: `CALL X(FIELD(A, ",", 1), B)` is two
# arguments, not four, and a naive comma count reports the wrong thing about
# code that is fine -- which is worse than not checking.
say "call arity"
arity_report=$(awk '
  FILENAME != last { last = FILENAME }
  # declarations: SUBROUTINE NAME(a, b, c)
  /^[[:space:]]*SUBROUTINE[[:space:]]+[A-Z0-9._]+\(/ {
      line = $0
      sub(/^[[:space:]]*SUBROUTINE[[:space:]]+/, "", line)
      name = line; sub(/\(.*$/, "", name)
      args = line; sub(/^[^(]*\(/, "", args); sub(/\).*$/, "", args)
      decl[name] = count_args(args)
      next
  }
  # A COMMENT IS NOT A CALL.  This read every line, so writing `CALL FOO(a, b)`
  # in a comment to explain what a caller does was reported as a real call with
  # the wrong arity -- a check that fails on its own documentation.
  /^[[:space:]]*\*/ { next }
  # calls: CALL NAME(a, b, c) -- skip CALL @VAR (dispatch by name)
  /CALL[[:space:]]+[A-Z0-9._]+[[:space:]]*\(/ {
      rest = $0
      while (match(rest, /CALL[[:space:]]+[A-Z0-9._]+[[:space:]]*\(/)) {
          seg = substr(rest, RSTART, RLENGTH)
          nm = seg; sub(/^CALL[[:space:]]+/, "", nm); sub(/[[:space:]]*\($/, "", nm)
          after = substr(rest, RSTART + RLENGTH)
          depth = 1; buf = ""; qq = ""
          for (i = 1; i <= length(after); i++) {
              c = substr(after, i, 1)
              if (qq != "") { if (c == qq) qq = ""; buf = buf c; continue }
              if (c == "\"" || c == "'"'"'") qq = c
              else if (c == "(") depth++
              else if (c == ")") { depth--; if (depth == 0) break }
              buf = buf c
          }
          calls[nm "\t" FILENAME "\t" FNR] = count_args(buf)
          rest = substr(after, i + 1)
      }
  }
  # Paren-aware AND quote-aware.  A comma inside a string is not a separator:
  # CMD.ADD("FIXPERMS", "hand them over, or move to a new one", "MVPKG.FIXPERMS")
  # is three arguments, and counting four reported a fault in correct code --
  # which is the one thing a check like this must never do.
  function count_args(a,   i, c, d, n, q) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", a)
      if (a == "") return 0
      d = 0; n = 1; q = ""
      for (i = 1; i <= length(a); i++) {
          c = substr(a, i, 1)
          if (q != "") { if (c == q) q = ""; continue }
          if (c == "\"" || c == "'"'"'") q = c
          else if (c == "(") d++
          else if (c == ")") d--
          else if (c == "," && d == 0) n++
      }
      return n
  }
  END {
      for (k in calls) {
          split(k, p, "\t")
          if (p[1] in decl && calls[k] != decl[p[1]])
              printf "%s:%s calls %s with %d, declared with %d\n", p[2], p[3], p[1], calls[k], decl[p[1]]
      }
  }
' $SRC)
if [ -n "$arity_report" ]; then
  bad "every CALL matches its SUBROUTINE's argument count" "$(printf '%s' "$arity_report" | head -6)"
else
  ok "every CALL matches its SUBROUTINE's argument count"
fi

say "the environment and file seams"
envleak=""
for f in $SRC; do
  case "$f" in */MVPKG.SH|*/MVPKG.ENV|*/MVPKG.FILE) continue;; esac
  grep -vE '^[[:space:]]*[*]' "$f" | grep -qE '\bGETENV[[:space:]]*\(' && envleak="$envleak $f"
done
if [ -z "$envleak" ]; then ok "GETENV appears only in the seams (use MVPKG.ENV)"
else bad "GETENV appears only in the seams" "also in:$envleak"; fi

fileleak=""
for f in $SRC; do
  case "$f" in */MVPKG.SH|*/MVPKG.SH.RM|*/MVPKG.ENV|*/MVPKG.FILE) continue;; esac
  grep -vE '^[[:space:]]*[*]' "$f" | grep -qE '\bOS(READ|WRITE|DELETE)\b' && fileleak="$fileleak $f"
done
if [ -z "$fileleak" ]; then ok "OSREAD/OSWRITE appear only in the seams (use MVPKG.FILE)"
else bad "OSREAD/OSWRITE appear only in the seams" "also in:$fileleak"; fi

# --- 12. no $IFDEF nested inside an $ELSE -----------------------------------
# Compiles on UniData, fails on UniVerse.  Flat guards instead, one per platform.
nested=""
for f in $SRC; do
  if awk 'BEGIN{e=0}
          /^[[:space:]]*[$]ELSE/{e=1; next}
          /^[[:space:]]*[$]ENDIF/{e=0; next}
          e && /^[[:space:]]*[$]IFDEF/{found=1}
          END{exit !found}' "$f"; then nested="$nested $f"; fi
done
if [ -z "$nested" ]; then ok "no \$IFDEF nested inside an \$ELSE (uv rejects it)"
else bad "no \$IFDEF nested inside an \$ELSE" "found in:$nested"; fi

# --- 9. an unguarded MVPKGOS op must exist in BOTH seams --------------------
# MVPKGOS is two files -- BP/MVPKGOS is the MVX seam, udt/MVPKGOS serves udt, uv
# and jbase -- and they had grown two names for one operation: MVX spelled the
# recursive delete RMRF and had no RMDIR, the other spelled it RMDIR and had no
# RMRF.  MVPKG.ONE called RMRF with no guard, so on all three MV ports it
# reached nothing, fell through to "unknown op", and the package directory was
# never cleared before the new version was unpacked over it.  A leftover _<PROG>
# object then shadowed the source shipped beside it, and stray files were
# compiled and cataloged as if they belonged to the package (#130).
#
# Nothing failed.  The one call that would have said so had its RESULT
# overwritten by the next call before it was read.
#
# A call INSIDE a platform guard is fine -- that is how MVPKG.REMOVE reaches
# each seam's own spelling -- so only unguarded calls are checked here.
say "the MVPKGOS seam"
mvxops=$(grep -oE 'CASE OP = "[A-Z.]+"' BP/MVPKGOS | grep -oE '"[A-Z.]+"' | tr -d '"' | sort -u)
mvops=$(grep -oE 'CASE OP = "[A-Z.]+"( OR OP = "[A-Z.]+")*' udt/MVPKGOS | grep -oE '"[A-Z.]+"' | tr -d '"' | sort -u)
missing=""
for f in $SRC; do
  case "$f" in */MVPKGOS) continue;; esac
  # ops called at guard depth 0 only
  for op in $(awk '
      /^[[:space:]]*[$]IFDEF/ || /^[[:space:]]*[$]IFNDEF/ { d++; next }
      /^[[:space:]]*[$]ENDIF/ { if (d>0) d--; next }
      /^[[:space:]]*\*/ { next }
      d == 0 && /CALL MVPKGOS\(/ {
         while (match($0, /CALL MVPKGOS\("[A-Z.]+"/)) {
            s = substr($0, RSTART, RLENGTH); gsub(/.*"/, "", s)
            t = substr($0, RSTART, RLENGTH); sub(/CALL MVPKGOS\("/, "", t); sub(/"$/, "", t)
            print t
            $0 = substr($0, RSTART + RLENGTH)
         }
      }' "$f"); do
    echo "$mvxops" | grep -qx "$op" || missing="$missing $f:$op:missing-from-BP/MVPKGOS"
    echo "$mvops"  | grep -qx "$op" || missing="$missing $f:$op:missing-from-udt/MVPKGOS"
  done
done
if [ -z "$missing" ]; then
  ok "every unguarded MVPKGOS op exists in both seams"
else
  bad "every unguarded MVPKGOS op exists in both seams" "$(printf '%s' "$missing" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')"
fi

# --- 10. one manifest, and it is mvpkg.json ------------------------------------
# There were two: PKG carried name, version, description, systems and
# dependencies as bare lines, and mvpkg.json carries the same plus what PKG had
# no room for.  Nothing kept them in step, so they drifted -- mvpkg's PKG line 2
# said "1.3" while its mvpkg.json said "1.3.0", and the json package shipped the
# two disagreeing about which system a dependency applied to (mvx-lang/json#23).
# The registry only ever read mvpkg.json.
say "one manifest"
if [ -e PKG ]; then
  bad "PKG is gone; mvpkg.json is the manifest" "PKG still exists in the repo root"
else
  ok "PKG is gone; mvpkg.json is the manifest"
fi
readers=""
for f in $SRC; do
  grep -vE '^\s*\*' "$f" | grep -qE '"PKG"' && readers="$readers $f"
done
for f in $(ls ./*.sh udt/*.sh uv/*.sh jbase/*.sh 2>/dev/null); do
  grep -vE '^\s*#' "$f" | grep -qE '/PKG"|/PKG |\$HERE/PKG|\$ROOT/PKG' && readers="$readers $f"
done
if [ -z "$readers" ]; then
  ok "nothing reads a PKG manifest"
else
  bad "nothing reads a PKG manifest" "still read by:$readers"
fi

# --- 11. a seam function is declared per platform, never bare ----------------
# HTTPGET, HTTPGETFILE, HTTPPOST, JSONDECODE and MAPFIELD are the names the client
# needs BEFORE the packages that provide them are installed, which is the whole
# of what mvpkg does first.  It ships its own bootstrap copies: jBASE catalogs
# them under the BARE names, so a bare DEFFUN finds them; udt and uv catalog
# them PREFIXED (MVPKG.MAPFIELD ...) and the CALLING clause is what reaches
# them.
#
# #116 collapsed the three arms in MVPKG.META and MVPKG.ONE to one bare
# declaration, on the premise that the dependency is the seam.  True once a
# package is deployed; false before one is -- and a fresh UniData or UniVerse
# account could not install anything at all (#133):
#
#     Program "MVPKG.META": Line 41, Unable to load subroutine.
#
# So: bare is correct INSIDE $IFDEF JBASE, and wrong at guard depth 0.
say "the seam declarations"
seambare=""
for f in $SRC; do
  case "$f" in */MVPKG.SH|*/MVPKGOS) continue;; esac
  hits=$(awk '
      /^[[:space:]]*[$]IFDEF/ || /^[[:space:]]*[$]IFNDEF/ { d++; next }
      /^[[:space:]]*[$]ENDIF/ { if (d>0) d--; next }
      /^[[:space:]]*\*/ { next }
      d == 0 && /^[[:space:]]*DEFFUN[[:space:]]+(HTTPGET|HTTPGETFILE|HTTPPOST|JSONDECODE|MAPFIELD|MVPKG.HTTPPOST)[[:space:]]*\(/ {
         line = $0
         sub(/^[[:space:]]*DEFFUN[[:space:]]+/, "", line)
         sub(/[[:space:]]*\(.*$/, "", line)
         print line
      }' "$f")
  for h in $hits; do seambare="$seambare $f:$h"; done
done
if [ -z "$seambare" ]; then
  ok "no seam function is declared outside a platform guard"
else
  bad "no seam function is declared outside a platform guard" "bare:$seambare"
fi

printf '\n%s\n' "source-checks: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
