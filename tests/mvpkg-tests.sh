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
# The first line of a PROBE program, as a printf format taking the probe's name.
# The mvx shim below clears it; see the note there.
PROBEHDR='   PROGRAM %s\n'
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
    # MVX HAS NO `PROGRAM' STATEMENT, and every probe below was built with one:
    #
    #     TMVSH1:1: expected '=' in assignment
    #
    # so each one failed to compile and the suite then ran a verb that was never
    # cataloged.  Ten assertions read `verb "TMVSH1" not found' -- and the four
    # phrased as "this string must NOT appear" PASSED on that, because a missing
    # verb's message does not contain the string either.  So the mvx column was
    # part failure, part decoration, and the decoration is the worse half.
    PROBEHDR=""
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
  printf "$PROBEHDR" "$n" > "$ACCT/BP/$n"
  printf '$INCLUDE MVPKG.INC PLATFORM.H\n%s\n' "$body" >> "$ACCT/BP/$n"
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

OUT=$(MVPKG_TEST_VAR=env-readable PROBE TMVENV '   CALL MVPKG.ENV("MVPKG_TEST_VAR", V)
   PRINT "V=":V
   CALL MVPKG.ENV("MVPKG_DEFINITELY_UNSET_VAR", U)
   PRINT "U=[":U:"]"')
t  "the env seam reads a set variable"      "V=env-readable" "$OUT"
t  "the env seam returns empty when unset"  "U=[]"           "$OUT"

# The file seam, likewise: OSREAD/OSWRITE do not exist on uv, so this has to go
# through MVPKG.FILE to be assertable on all four.
OUT=$(PROBE TMVFILE '   TF = "/tmp/mvpkg-fileseam.txt"
   D = "alpha" : @AM : "beta"
   CALL MVPKG.FILE("WRITE", TF, D, OK1)
   R = ""
   CALL MVPKG.FILE("READ", TF, R, OK2)
   PRINT "W=":OK1:" R=":OK2:" N=":DCOUNT(R, @AM):" A=[":R<1>:"] B=[":R<2>:"]"
   CALL MVPKG.FILE("DELETE", TF, D2, OK3)
   CALL MVPKG.FILE("READ", TF, R2, OK4)
   PRINT "AFTERDEL=":OK4')
t  "the file seam writes and reads back"    "W=1 R=1 N=2 A=[alpha] B=[beta]" "$OUT"
t  "the file seam deletes"                  "AFTERDEL=0"     "$OUT"

# ===========================================================================
say "the client"
# THE COMMAND FRAMEWORK IS A DEPENDENCY, NOT PART OF THE CLIENT (#158).  mvpkg
# used to carry a copy of cmd under cmd's own names, so the usage screen worked
# in any account the client was cataloged in -- and collided with the real cmd
# package wherever both landed.  It is mvx-lang/cmd's job now, which means an
# account that has the client but not its dependency cannot print a usage
# screen, and says so instead.  Skip the framework-driven checks there rather
# than report a failure the account explains: MVPKG install mvx-lang/cmd.
OUT=$(RUN "MVPKG")
HAVECMD=1
case "$OUT" in *"the cmd package is not installed"*) HAVECMD=0 ;; esac
tcmd() { # tcmd <name> <needle> <output> — a check that needs the framework
  if [ "$HAVECMD" = 1 ]; then t "$1" "$2" "$3"
  else skip "$1" "mvx-lang/cmd is not installed in this account"; fi
}
tcmd "no arguments prints the usage"        "usage: MVPKG"   "$OUT"
tcmd "usage lists install"                    "install"        "$OUT"
tn "usage does not leak a shell error"      "!mkdir"         "$OUT"

OUT=$(RUN "MVPKG help")
tcmd "help prints the usage"                  "usage: MVPKG"   "$OUT"

OUT=$(RUN "MVPKG config")
tcmd "config reports the registry"            "registry:"      "$OUT"
tcmd "config reports the store"               "store:"         "$OUT"
tn "config store is not the filesystem root" "store:    /mvpkg" "$OUT"
tn "config does not leak a shell error"     "No such file or directory" "$OUT"

OUT=$(RUN "MVPKG list")
tn "list does not leak a shell error"       "!"              "$OUT"

OUT=$(RUN "MVPKG definitely-not-a-command")
tcmd "an unknown command is rejected"         "unknown command" "$OUT"

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
  uv)    t "PLATFORM.H still says UV"       '$DEFINE UV'     "$AFTER";;
  mvx)   t "PLATFORM.H names the master"    'MVMASTER'       "$AFTER";;
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

# ===========================================================================
say "will the published build load here? (MVPKGOS LDCHECK, #177)"
# The question CLIBCHECK cannot answer.  A package declares the libraries its
# SOURCE links -- mvx-lang/git declares libgit2.so:>=1.7,<2.8 -- and that range
# is satisfied on a host carrying libgit2 1.9 while the prebuilt in the artifact,
# linked against 1.7, still cannot load.  So this asks the shipped file.
#
# MVX ONLY: every other port relinks the package's C on the host at install
# time, so none of them ships a prebuilt whose DT_NEEDED could name a soname
# this machine lacks.
case "$PLATFORM" in
  mvx)
    LDW="${TMPDIR:-/tmp}/mvpkg-ldcheck.$$"
    rm -rf "$LDW"; mkdir -p "$LDW/pkg/LIB" "$LDW/bin"

    # A STUB ldd, so this runs on the machine mvx is DEVELOPED on and not only
    # on the one it ships to.  It answers in ldd's own format -- a leading tab,
    # "name => not found" -- for the two names the fixture is about, and that
    # format is the whole of what LDFILE parses.
    cat > "$LDW/bin/ldd" <<'LDDEOF'
#!/bin/sh
printf '\tlibzfoo.so.9 => not found\n'
printf '\tlibzself.so.1 => not found\n'
printf '\tlibc.so.6 => /lib/libc.so.6 (0x0)\n'
LDDEOF
    chmod +x "$LDW/bin/ldd"
    : > "$LDW/pkg/LIB/libmvxext_zz.so"

    # THE GRANT, WITHOUT WHICH THIS CHECK IS INERT.  OSEXEC is permit-gated at
    # every tier below unrestricted, so an account that does not grant ldd gets
    # "" from LDCHECK -- the right answer, and indistinguishable from a clean
    # package.  Granting it here is therefore part of the fixture, not a
    # convenience: the first run of these tests failed on exactly this.
    PERMD="$ACCT/.mvx-private"; PERMF="$PERMD/permissions"
    PERMSAVE=""
    mkdir -p "$PERMD"
    if [ -f "$PERMF" ]; then PERMSAVE="$PERMF.mvpkgtest.$$"; cp "$PERMF" "$PERMSAVE"; fi
    printf 'permit * = ldd\n' >> "$PERMF"

    LD() { PATH="$LDW/bin:$PATH" MVPKG_LDCHECK=force PROBE "$1" "$2"; }

    OUT=$(LD TMVLD1 '   CALL MVPKGOS("LDCHECK", "'"$LDW"'/pkg", "", R)
   PRINT "R=[" : CHANGE(R, @AM, " | ") : "]"')
    t  "a soname the host does not have is reported"  "libzfoo.so.9"  "$OUT"
    t  "and it says which file needs it"              "libmvxext_zz.so: libzfoo.so.9" "$OUT"
    tn "a resolved library is not reported"           "libc.so.6"     "$OUT"

    # THE SELF-SUPPLIED HALF.  A package whose extension links a library it
    # ships itself must not have its own file called missing: ldd cannot see
    # into the package's LIB, so the name is filtered against what is there.
    : > "$LDW/pkg/LIB/libzself.so.1"
    OUT=$(LD TMVLD2 '   CALL MVPKGOS("LDCHECK", "'"$LDW"'/pkg", "", R)
   PRINT "R=[" : CHANGE(R, @AM, " | ") : "]"')
    # THE PAIR, NOT THE NAME.  Entries read "<file>: <soname>", and the stub ldd
    # answers for every file in the tree -- including the libzself.so.1 that was
    # just put there -- so the bare name appears on the left of its own line
    # whatever the filter does.  What must not appear is anything NEEDING it.
    tn "a soname the package ships itself is not reported" ": libzself.so.1" "$OUT"
    t  "while the genuinely missing one still is"          "libzfoo.so.9"  "$OUT"

    # THE FALSIFYING HALF of the whole section: with no ldd to ask, this must
    # report NOTHING rather than refuse the package.  Without this, a check that
    # had quietly stopped working would read exactly like a clean package.
    #
    # BUILT WITH THE NORMAL PATH AND RUN WITHOUT ONE.  Taking PATH away for the
    # whole PROBE takes it away from the COMPILE too, so the first version of
    # this assertion was reading `verb "TMVLD3" not found' and calling it a
    # missing ldd.  Only the ldd spawn looks at PATH; the verb itself is run by
    # absolute path.
    LD TMVLD3 '   CALL MVPKGOS("LDCHECK", "'"$LDW"'/pkg", "", R)
   PRINT "R=[" : CHANGE(R, @AM, " | ") : "]"' >/dev/null 2>&1
    OUT=$(MVPKG_LDCHECK=force PATH="$LDW/noldd" RUN TMVLD3)
    t  "with no ldd to ask it reports nothing, not a refusal" "R=[]" "$OUT"
    tn "and it does not fail looking for one"                 "not found" "$OUT"

    # AND A REAL ELF OBJECT, where there is a real ldd to read it.  libzbar
    # links libzfoo and libzfoo is then taken away, so its DT_NEEDED names a
    # library this host genuinely does not have -- no patchelf needed.
    if [ "$(uname -s)" = Linux ] && command -v cc >/dev/null 2>&1 && command -v ldd >/dev/null 2>&1; then
      rm -rf "$LDW/real"; mkdir -p "$LDW/real/LIB"
      echo 'int zfoo(void){return 1;}' > "$LDW/foo.c"
      echo 'int zfoo(void); int zbar(void){return zfoo();}' > "$LDW/bar.c"
      if cc -shared -fPIC -o "$LDW/libzfoo.so" "$LDW/foo.c" 2>/dev/null &&
         cc -shared -fPIC -o "$LDW/real/LIB/libzbar.so" "$LDW/bar.c" \
            -L"$LDW" -lzfoo 2>/dev/null; then
        mv "$LDW/libzfoo.so" "$LDW/libzfoo.so.away"
        OUT=$(MVPKG_LDCHECK=force PROBE TMVLD4 '   CALL MVPKGOS("LDCHECK", "'"$LDW"'/real", "", R)
   PRINT "R=[" : CHANGE(R, @AM, " | ") : "]"')
        t  "a real object's missing dependency is read off the file" "libzfoo.so" "$OUT"
        # and the pair: give the package the library and it is clean again
        cp "$LDW/libzfoo.so.away" "$LDW/real/LIB/libzfoo.so"
        OUT=$(MVPKG_LDCHECK=force PROBE TMVLD5 '   CALL MVPKGOS("LDCHECK", "'"$LDW"'/real", "", R)
   PRINT "R=[" : CHANGE(R, @AM, " | ") : "]"')
        t  "and supplying it clears the report"                      "R=[]"       "$OUT"
      else
        skip "a real object's missing dependency is read off the file" "cc could not build the fixture"
      fi
    else
      skip "a real object's missing dependency is read off the file" "needs Linux with cc and ldd"
    fi
    rm -rf "$LDW"
    if [ -n "$PERMSAVE" ]; then mv "$PERMSAVE" "$PERMF"
    else rm -f "$PERMF"; rmdir "$PERMD" 2>/dev/null || true; fi
    ;;
  *) skip "the load check" "LDCHECK is mvx-only -- other ports relink on the host";;
esac

# ===========================================================================
say "resolving the source artifact (MVPKG.SRCURL / META<13>, #177)"
# Two facts the client needs before it can build a source release in place of a
# prebuilt that will not load: whether this version publishes source at all, and
# where that source is.  Both come off the registry, so this needs one -- a
# canned one, because the assertion is about decoding the response, not about
# what is published today.
#
# sourceIncluded IS A JSON BOOLEAN and JSONDECODE answers "" for one (measured),
# so it is scanned out of the body.  That is the fact this guards: the field was
# present, correct and invisible, which is how `systems' behaved before #164.
if command -v python3 >/dev/null 2>&1; then
  RPORT=${MVPKG_TEST_PORT:-19177}
  RW="${TMPDIR:-/tmp}/mvpkg-reg.$$"; mkdir -p "$RW"
  cat > "$RW/reg.py" <<'REGEOF'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
BIN = {"name": "zz/demo", "version": "1.0.0", "selected": "binary",
       "tarball": "https://example.invalid/zz_demo-1.0.0-mvx-linux-x86_64-le.tar.gz",
       "description": "d", "dependencies": "", "devDependencies": "",
       "sourceIncluded": True, "systems": ["mvx"], "versions": "1.0.0",
       "provides": "", "clibs": "libzfoo.so", "srcrepo": ""}
SRC = dict(BIN, selected="source",
           tarball="https://example.invalid/zz_demo-1.0.0-source.tar.gz")
NOSRC = dict(BIN, name="zz/binonly", sourceIncluded=False)
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if "binonly" in self.path:   d = NOSRC
        elif "system=" in self.path: d = BIN
        else:                        d = SRC
        b = json.dumps(d).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers()
        self.wfile.write(b)
    def log_message(self, *a): pass
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
REGEOF
  python3 "$RW/reg.py" "$RPORT" >/dev/null 2>&1 &
  RPID=$!
  # Wait for it rather than sleeping a guessed interval: a registry that is not
  # up yet reads as "package not found", which is a passing-looking skip.
  #
  # NOT /dev/tcp: that is a bash feature and this suite is run with `sh', which
  # on a Linux runner is dash -- where the probe would always fail and the whole
  # section would skip itself quietly.  python3 is already required here.
  RUP=""
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if python3 -c 'import socket,sys
s=socket.socket()
s.settimeout(0.5)
sys.exit(0 if s.connect_ex(("127.0.0.1", int(sys.argv[1]))) == 0 else 1)' "$RPORT" 2>/dev/null
    then RUP=1; break; fi
    sleep 1
  done
  if [ -z "$RUP" ]; then
    skip "the source artifact resolver" "the canned registry did not come up on $RPORT"
  else
    RURL="http://127.0.0.1:$RPORT"
    OUT=$(PROBE TMVSRC1 '   CALL MVPKG.META("zz/demo", "", "'"$RURL"'", M)
   PRINT "SEL=" : M<10>
   PRINT "SRC=[" : M<13> : "]"
   PRINT "CLIBS=" : M<9>')
    t  "the platform query gets the binary artifact"   "SEL=binary" "$OUT"
    t  "and a published source artifact is seen"       "SRC=[1]"    "$OUT"

    # THE FALSIFYING HALF: a binary-only package must NOT report source, or the
    # client would re-resolve on faith and download the same binary again --
    # which the registry hands back as `selected: source' for want of anything
    # else to give (indexRelease sets tarball to the first binary).
    OUT=$(PROBE TMVSRC2 '   CALL MVPKG.META("zz/binonly", "", "'"$RURL"'", M)
   PRINT "SRC=[" : M<13> : "]"')
    t  "a binary-only package reports no source"       "SRC=[]"     "$OUT"

    OUT=$(PROBE TMVSRC3 '   CALL MVPKG.SRCURL("zz/demo", "1.0.0", "'"$RURL"'", U)
   PRINT "URL=" : U')
    t  "the resolver asks without the platform and gets source" "zz_demo-1.0.0-source.tar.gz" "$OUT"
    tn "and never hands back the binary"               "x86_64"     "$OUT"
  fi
  { kill "$RPID"; wait "$RPID"; } 2>/dev/null
  rm -rf "$RW"
else
  skip "the source artifact resolver" "no python3 for the canned registry"
fi

# TMVFILE was not on this list and so was left in BP/ by every run -- in a repo
# that IS the account, which means an untracked stray beside the sources.
rm -f "$ACCT"/BP/TMVSH? "$ACCT"/BP/TMVMAS "$ACCT"/BP/TMVENV "$ACCT"/BP/TMVFILE 2>/dev/null
rm -f "$ACCT"/BP/TMVLD? "$ACCT"/BP/TMVSRC? 2>/dev/null
printf '\nmvpkg-tests: %s passed, %s failed, %s skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
