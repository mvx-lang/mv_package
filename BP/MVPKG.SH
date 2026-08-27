* MVPKG.SH - run one shell command line, and say what it printed and whether it
* worked.  Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see LICENSE).
*
* THE ONE PLACE THIS CLIENT REACHES A SHELL.  Everything else calls here, so a
* platform that spells the escape differently is one arm in this file rather
* than an edit at twenty-one call sites.
*
*   SHCMD   in   the command line, written exactly as for /bin/sh: pipes,
*                redirection, $? and quotes all mean what they normally mean.
*   SHOUT   out  what it printed on stdout (@AM per line), "" if it redirected.
*   SHSTAT  out  its exit status; -1 if that could not be determined.
*
* WHY jBASE NEEDS ITS OWN ARM.  On UniData the `!` prefix hands the line to a
* shell, so the shell does the quoting and the pipes.  jBASE has no `!`: EXECUTE
* reaches the OS DIRECTLY, argv-style.  There is no shell, so `|`, `>` and `$?`
* are not special, and quotes arrive as literal characters rather than grouping
* anything.  `sh -c "..."` does not rescue it either, for exactly that reason --
* the quotes meant to hold the command together are passed through as text and
* the command arrives split across argv.
*
* So the command is written to a FILE and sh is run on the file.  The file is
* the quoting boundary: the command text is never re-parsed by anything between
* here and sh, so it is used exactly as written and every shell feature works.
* The EXECUTE line itself then contains nothing but a path -- no spaces to
* group, no quotes to survive.
   SUBROUTINE MVPKG.SH(SHCMD, SHOUT, SHSTAT)
$INCLUDE MVPKG.INC PLATFORM.H
   SHOUT = "" ; SHSTAT = -1
   IF TRIM(SHCMD) = "" THEN RETURN
$IFDEF JBASE
* A name no other session can collide with: @USERNO is this port, and the
* counter makes repeated calls within one program distinct.
   COMMON /MVPKGSH/ SHSEQ
   SHSEQ += 1
   SHTMP = GETENV("TMPDIR") ; IF SHTMP = "" THEN SHTMP = "/tmp"
   SHBASE = SHTMP : "/mvpkgsh." : @USERNO : "." : SHSEQ
   SHF = SHBASE : ".sh"
   SHR = SHBASE : ".rc"
* THE REDIRECTION GOES IN THE SCRIPT, NOT ON THE EXECUTE LINE.  Writing
* `EXECUTE "sh f > out 2>&1"` would hand jBASE the > and the 2>&1 as literal
* argv words, which is the very problem this routine exists to solve.  The
* EXECUTE line therefore carries a command and a path and nothing else; stdout
* comes back through CAPTURING, and only the status needs a file.
   SHSCRIPT = SHCMD
   SHSCRIPT<-1> = "echo $? > " : SHR
   OSWRITE SHSCRIPT ON SHF
   EXECUTE "sh " : SHF CAPTURING SHOUT
   OSREAD SHRC FROM SHR ELSE SHRC = ""
   SHRC = TRIM(FIELD(SHRC, CHAR(10), 1))
   IF NUM(SHRC) AND SHRC # "" THEN SHSTAT = SHRC + 0
   CALL MVPKG.SH.RM(SHF, SHR)
$ELSE
* UniData / UniVerse: `!` hands the whole line to a shell, which is all this
* needs.  The status is asked for the same way it is on jBASE -- by appending a
* line to the command -- so a caller gets a status on every platform rather
* than only where it happened to be wired up before.
   SHTMP = GETENV("TMPDIR") ; IF SHTMP = "" THEN SHTMP = "/tmp"
   SHR = SHTMP : "/mvpkgsh.rc." : @USERNO
   EXECUTE '!' : SHCMD : ' ; echo $? > ' : SHR CAPTURING SHOUT
   OSREAD SHRC FROM SHR ELSE SHRC = ""
   SHRC = TRIM(FIELD(SHRC, CHAR(10), 1))
   IF NUM(SHRC) AND SHRC # "" THEN SHSTAT = SHRC + 0
   EXECUTE '!rm -f ' : SHR CAPTURING SHJUNK
$ENDIF
   RETURN
