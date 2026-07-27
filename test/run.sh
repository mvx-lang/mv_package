#!/bin/sh
# mv-package — end-to-end install-loop test.
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see ../LICENSE).
#
#   MVX_HOME=/path/to/mvx-lang ./test/run.sh
#
# Proves the whole loop with no external dependency: build the MVPKG client,
# register a throwaway fixture package, start the registry on a free port, then
# `MVPKG install` it and assert the fixture's files land in the destination.
# Needs node and a built mvx-lang toolchain (http + json in its system account).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
: "${MVX_HOME:?set MVX_HOME to your mvx-lang checkout (with a built toolchain)}"
MVX="$MVX_HOME/build/bin/mvx"
[ -x "$MVX" ] || { echo "mvx not found under $MVX_HOME/build/bin" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "node not found; skipping" >&2; exit 0; }
export MVX_DRIVERS="$MVX_HOME/build/lib"

WORK="$(mktemp -d)"
trap '{ kill "$REGPID" && wait "$REGPID"; } 2>/dev/null; rm -rf "$WORK" "$ROOT/server/registry/demo"' EXIT

# 1. build the client
MVX_HOME="$MVX_HOME" "$ROOT/build.sh" >/dev/null

# 2. a fixture "package": an account-shaped dir with a recognisable marker
FIX="$WORK/fixture"; mkdir -p "$FIX/BP"
printf 'CRT "hello from demo"\n' > "$FIX/BP/DEMO"
printf 'demo-marker\n' > "$FIX/MARKER"
"$ROOT/server/mkrelease.sh" "$FIX" demo 1.0 "a throwaway fixture package" >/dev/null

# 3. registry on an OS-chosen free port
PORT="$(node -e 'const s=require("net").createServer();s.listen(0,()=>{console.log(s.address().port);s.close()})')"
node "$ROOT/server/server.js" "$PORT" >"$WORK/reg.log" 2>&1 &
REGPID=$!
sleep 1

export MVPKG_REGISTRY="http://127.0.0.1:$PORT"
DEST="$WORK/installed"

# 4. install and assert
MVXPRIV=unrestricted "$MVX" -a "$ROOT" -c "MVPKG install demo $DEST" >"$WORK/out" 2>&1
cat "$WORK/out"

fail=0
grep -q "installed demo 1.0" "$WORK/out"   || { echo "FAIL: no install confirmation"; fail=1; }
[ -f "$DEST/MARKER" ]                       || { echo "FAIL: MARKER not installed"; fail=1; }
[ -f "$DEST/BP/DEMO" ]                       || { echo "FAIL: BP/DEMO not installed"; fail=1; }
grep -q demo-marker "$DEST/MARKER" 2>/dev/null || { echo "FAIL: MARKER content wrong"; fail=1; }

# 5. a missing package must report cleanly, not install anything
MISS="$WORK/miss"
MVXPRIV=unrestricted "$MVX" -a "$ROOT" -c "MVPKG install nosuch $MISS" >"$WORK/miss.out" 2>&1
grep -q "not found in registry" "$WORK/miss.out" || { echo "FAIL: missing pkg not reported"; fail=1; }
[ -d "$MISS" ] && { echo "FAIL: missing pkg created a dest dir"; fail=1; }

if [ "$fail" = 0 ]; then echo "PASS: mv-package end-to-end install loop"; else exit 1; fi
