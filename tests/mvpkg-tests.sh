#!/usr/bin/env bash
# mvpkg — runtime test suite, driven through the MVPKG verb and the seam so it
# runs identically on MVX, UniData, UniVerse and jBASE.
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only.
#
# Assertion-based rather than golden-file, so it is platform-agnostic and
# legible in CI logs.  Requires an account with the client already compiled and
# cataloged (install.sh / build.sh has been run in it).
#
#   PLATFORM=jbase ACCT=/home/rocky/mpjb2 sh tests/mvpkg-tests.sh
#   PLATFORM=udt   ACCT=/home/rocky/mvpkg sh tests/mvpkg-tests.sh
#   PLATFORM=mvx   ACCT=. MVX=.../mvx     sh tests/mvpkg-tests.sh
#
# Exit non-zero if any assertion fails.
set -u
PLATFORM="${PLATFORM:-mvx}"
: "${ACCT:?set ACCT to an account with the mvpkg client cataloged}"
PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; }
skip() { SKIP=$((SKIP+1)); printf '  skip %s (%s)\n' "$1" "$2"; }
t()    { case "$3" in *"$2"*) ok "$1";; *) bad "$1" "$2" "$3";; esac; }
te()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
# tn NAME UNWANTED ACTUAL — the string must NOT appear
tn()   { case "$3" in *"$2"*) bad "$1" "NOT containing '$2'" "$3";; *) ok "$1";; esac; }
say()  { printf '\n%s\n' "$*"; }

# --- runtime shims: the one place that knows one system from another --------
case "$PLATFORM" in
  jbase)
    # jbase_env.sh reads variables it has not set, so `set -u` kills the shell
    # the moment it is sourced -- silently, before a single test runs.
    set +u
    . "${JBASE_ENV:-/opt/jbase/CurrentVersion/jbase_env.sh}" >/dev/null 2>&1 || true
    set -u
    RUN()   { ( cd "$ACCT" && printf '%s\nQUIT\n' "$*" | jsh 2>&1 | tr -d '\000' | grep -av '^QUIT:' ); }
    BUILD() { ( cd "$ACCT" && printf 'BASIC BP %s\nCATALOG BP %s\nQUIT\n' "$1" "$1" | jsh >/dev/null 2>&1 ); }
    ;;
  udt)
    UDTHOME="${UDTHOME:-/usr/ud83}"; export UDTHOME
    UDT="$UDTHOME/bin/udt"; export LANG="${LANG:-en_US.UTF-8}" TERM=dumb
    RUN()   { ( cd "$ACCT" && printf '%s\nQUIT\n' "$*" | "$UDT" 2>&1 | tr -d '\000' ); }
    BUILD() { ( cd "$ACCT" && printf 'BASIC BP %s\nCATALOG BP %s LOCAL FORCE\nQUIT\n' "$1" "$1" | "$UDT" >/dev/null 2>&1 ); }
    ;;
  uv)
    UVHOME="${UVHOME:-/usr/uv}"; export UVHOME TERM=dumb
    UV="$UVHOME/bin/uv"
    RUN()   { ( cd "$ACCT" && printf '%s\nQUIT\n' "$*" | "$UV" 2>&1 | tr -d '\000' ); }
    BUILD() { ( cd "$ACCT" && printf 'BASIC BP %s\nCATALOG BP %s\nQUIT\n' "$1" "$1" | "$UV" >/dev/null 2>&1 ); }
    ;;
  mvx)
    : "${MVX:?set MVX to the mvx runtime}"
    RUN()   { MVXPRIV="${MVXPRIV:-developer}" "$MVX" -a "$ACCT" -c "$*" 2>&1; }
    BUILD() { MVXPRIV=developer "$MVX" -a "$ACCT" -c "CATALOG BP $1" >/dev/null 2>&1; }
    ;;
  *) echo "unknown PLATFORM '$PLATFORM'" >&2; exit 2;;
esac

# PROBE <name> <basic-body> — compile, catalog and run a throwaway program in
# the account, echoing its output.  This is how the seam is tested directly
# rather than only through whatever verb happens to call it.
PROBE() {
  local n="$1" body="$2"
  # The include is what supplies MVMASTER and the platform guards.  Without it
  # a probe compiles and then dies on an undefined variable -- and an assertion
  # phrased as "the failure marker is absent" calls that a pass.
  printf '   PROGRAM %s\n$INCLUDE MVPKG.INC PLATFORM.H\n%s\n' "$n" "$body" > "$ACCT/BP/$n"
  BUILD "$n"
  RUN "$n"
}

printf 'mvpkg tests — PLATFORM=%s ACCT=%s\n' "$PLATFORM" "$ACCT"

# ===========================================================================
say "the shell seam (MVPKG.SH)"
# Every OS call in the client goes through here, so these four shapes are the
# whole contract.  The pipeline case is the one that cannot work on jBASE by
# any route that does not write the command to a file.
OUT=$(PROBE TMVSH1 '   CALL MVPKG.SH("echo seam-alive", O, S)
   PRINT "OUT=":TRIM(O)
   PRINT "ST=":S')
t  "runs a command and returns its stdout"  "OUT=seam-alive" "$OUT"
t  "a successful command reports status 0"  "ST=0"           "$OUT"

# The quote is built with CHAR(34) so this line passes through the shell, the
# heredoc and the BASIC compiler without any of them needing to escape it.
OUT=$(PROBE TMVSH2 '   Q = CHAR(34)
   CALL MVPKG.SH("echo " : Q : "a b c" : Q : " | tr a-z A-Z", O, S)
   PRINT "OUT=":TRIM(O)')
t  "a pipeline containing quotes works"     "OUT=A B C"      "$OUT"

OUT=$(PROBE TMVSH3 '   CALL MVPKG.SH("ls /definitely/not/here 2>/dev/null", O, S)
   PRINT "ST=":S')
tn "a failing command does NOT report 0"    "ST=0"           "$OUT"
tn "a failing command status is known"      "ST=-1"          "$OUT"

OUT=$(PROBE TMVSH4 '   TF = "/tmp/mvpkg-testprobe.txt"
   CALL MVPKG.SH("uname -s > " : TF : " 2>/dev/null", O, S)
   OSREAD R FROM TF ELSE R = "<none>"
   PRINT "FILE=":TRIM(R)
   CALL MVPKG.SH("rm -f " : TF, O2, S2)')
tn "redirection inside the command works"   "FILE=<none>"    "$OUT"

OUT=$(PROBE TMVSH5 '   CALL MVPKG.SH("", O, S)
   PRINT "OUT=[":TRIM(O):"] ST=":S')
t  "an empty command is a harmless no-op"   "OUT=[]"         "$OUT"

# ===========================================================================
say "platform facts from PLATFORM.H"
OUT=$(PROBE TMVMAS '   OPEN MVMASTER TO F ELSE
      PRINT "RESULT=openfailed-":MVMASTER
      STOP
   END
   PRINT "RESULT=opened-":MVMASTER')
case "$PLATFORM" in
  jbase) t "MVMASTER is MD and it opens"    "RESULT=opened-MD"  "$OUT";;
  *)     t "MVMASTER is VOC and it opens"   "RESULT=opened-VOC" "$OUT";;
esac

OUT=$(MVPKG_TEST_VAR=env-readable PROBE TMVENV '   PRINT "V=":GETENV("MVPKG_TEST_VAR")')
if [ "$PLATFORM" = mvx ] || [ "$PLATFORM" = jbase ] || [ "$PLATFORM" = udt ]; then
  t "GETENV reads the environment"          "V=env-readable" "$OUT"
else
  skip "GETENV reads the environment" "not wired for $PLATFORM"
fi

# ===========================================================================
say "the client"
OUT=$(RUN "MVPKG")
t  "no arguments prints the usage"          "usage: MVPKG"   "$OUT"
t  "usage lists install"                    "install"        "$OUT"
tn "usage does not leak a shell error"      "!mkdir"         "$OUT"

OUT=$(RUN "MVPKG help")
t  "help prints the usage"                  "usage: MVPKG"   "$OUT"

OUT=$(RUN "MVPKG config")
t  "config reports the registry"            "registry:"      "$OUT"
t  "config reports the store"               "store:"         "$OUT"
tn "config store is not the filesystem root" "store:    /mvpkg" "$OUT"
tn "config does not leak a shell error"     "No such file or directory" "$OUT"

OUT=$(RUN "MVPKG list")
tn "list does not leak a shell error"       "!"              "$OUT"

OUT=$(RUN "MVPKG definitely-not-a-command")
t  "an unknown command is rejected"         "unknown command" "$OUT"

# ===========================================================================
say "init does not damage the account it initialises"
# INCSETUP had only a UniData arm, so on jBASE `MVPKG init` overwrote the
# account's own PLATFORM.H with $DEFINE UDT -- after which every recompile
# silently took the UniData arm of every guard.
BEFORE=$(cat "$ACCT/MVPKG.INC/PLATFORM.H" 2>/dev/null || echo "<absent>")
OUT=$(RUN "MVPKG init -y")
t  "init reports success"                   "initialised"    "$OUT"
AFTER=$(cat "$ACCT/MVPKG.INC/PLATFORM.H" 2>/dev/null || echo "<absent>")
te "init leaves PLATFORM.H unchanged"       "$BEFORE"        "$AFTER"
case "$PLATFORM" in
  jbase) t "PLATFORM.H still says JBASE"    '$DEFINE JBASE'  "$AFTER";;
  udt)   t "PLATFORM.H still says UDT"      '$DEFINE UDT'    "$AFTER";;
  *)     skip "PLATFORM.H platform symbol" "not asserted for $PLATFORM";;
esac
# `CREATE.FILE DIR MVPKG.INC` reads DIR as the NAME on jBASE, silently creating
# a file called DIR and never the one asked for.
if [ -e "$ACCT/DIR" ]; then bad "init creates no stray DIR file" "no DIR" "DIR exists"
else ok "init creates no stray DIR file"; fi

OUT=$(RUN "MVPKG init -y")
t  "init is idempotent"                     "initialised"    "$OUT"

# the store the config names must actually exist -- a store that was never
# created reads as "no packages installed", which looks like success
STORE=$(RUN "MVPKG config" | sed -n 's/^ *store: *//p' | head -1 | tr -d ' \r')
if [ -n "$STORE" ] && [ -d "$STORE" ]; then ok "the store directory named by config exists"
elif [ -z "$STORE" ]; then bad "the store directory named by config exists" "a path" "<none reported>"
else bad "the store directory named by config exists" "$STORE to exist" "missing"; fi

rm -f "$ACCT"/BP/TMVSH? "$ACCT"/BP/TMVMAS "$ACCT"/BP/TMVENV 2>/dev/null
printf '\nmvpkg-tests: %s passed, %s failed, %s skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
