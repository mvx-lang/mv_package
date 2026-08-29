# mvpkg tests

Three suites, in increasing order of what they need to run.

| suite | needs | what it is for |
|---|---|---|
| `source-checks.sh` | nothing | portability rules the sources must obey |
| `self-check.sh` | nothing | proves `source-checks.sh` can actually fail |
| `mvpkg-tests.sh` | a built account | the seam and the client, run for real |

## `source-checks.sh` — no MV system required

Reads the sources and asserts nine properties. Every one exists because that
exact thing broke, and **broke silently**: each compiled cleanly on at least one
system and failed at run time on another, which is why a clean compile is not
the test.

```bash
sh tests/source-checks.sh
```

It catches: a shell escape outside `MVPKG.SH`; `$IFDEF` on a PLATFORM.H symbol
without the include (silently false); the include placed before `SUBROUTINE`; a
valued `$DEFINE` inside a guard (leaks on jBASE regardless of the guard);
`$IFDEF` combining symbols (no system supports it); a hardcoded `OPEN "VOC"`
(jBASE has `MD`); jBASE reserved words as identifiers; `LOCATE` Format 2; and an
unguarded `DEFFUN … CALLING`.

## `self-check.sh` — proves the checks are not decoration

Breaks a throwaway copy of the tree in each of the nine ways and asserts the
check goes red.

```bash
sh tests/self-check.sh
```

This is not ceremony. Four of the nine checks were decoration when first
written — they used `\s` and `\b`, which BSD grep does not know, so the patterns
matched nothing and every run was green.

## `mvpkg-tests.sh` — needs an account with the client cataloged

```bash
PLATFORM=jbase ACCT=/path/to/account sh tests/mvpkg-tests.sh
PLATFORM=udt   ACCT=/path/to/account sh tests/mvpkg-tests.sh
PLATFORM=mvx   ACCT=. MVX=/path/to/mvx sh tests/mvpkg-tests.sh
```

Assertion-based rather than golden-file, so one suite runs on every platform.
Covers the shell seam directly (stdout, a pipeline containing quotes, a failing
command's status, redirection, an empty command), the facts PLATFORM.H supplies
(`MVMASTER` opens and is the right dictionary; `GETENV` reads the environment),
the client's own commands, and that **`MVPKG init` does not damage the account
it initialises** — which it did on jBASE, by overwriting PLATFORM.H with the
UniData one.

### Writing a test here

Assert a **positive** fact. `tn` ("this string is absent") is available but is
the weaker form: an assertion phrased as "the failure marker did not appear" is
satisfied by the probe crashing before it could print anything, and one of these
tests passed that way until it was rewritten to assert what *did* happen.

`PROBE` writes, compiles and runs a throwaway program in the account; it emits
`$INCLUDE MVPKG.INC PLATFORM.H` for you, without which `MVMASTER` and every
guard are undefined.
