* MVPKG.SH - run one shell command line, and say what it printed and whether it
* worked.  Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see LICENSE).
*
* THE ONE PLACE THIS CLIENT REACHES A SHELL.  Everything else calls here, so a
* platform that spells the escape differently is one arm in this file rather
* than an edit at every call site.
*
*   SHCMD   in   the command line, written exactly as for /bin/sh: pipes,
*                redirection, $? and quotes all mean what they normally mean.
*   SHOUT   out  what it printed on stdout, "" if it redirected.
*   SHSTAT  out  its exit status; -1 if that could not be determined.
*
* THREE SPELLINGS OF "RUN THIS".  UniData and MVX take `!cmd`.  jBASE has no `!`
* at all -- EXECUTE reaches the OS directly, argv-style, so nothing is a shell
* metacharacter and quotes arrive literally.  UniVerse has no `!` either (its
* verb table simply has no "!echo") and wants SH -c.
*
* On the two that need it the command goes into a FILE and sh is run on the
* file.  The file is the quoting boundary: nothing re-parses the command text
* between here and sh, so every shell feature works, and the EXECUTE line is
* left carrying a path -- which has nothing in it that needs quoting.  Wrapping
* the command in another layer of quotes cannot work, because the command is
* itself allowed to contain quotes.
*
* FLAT GUARDS, NOT NESTED ONES.  An $IFDEF inside an $ELSE compiles on UniData
* and fails on UniVerse, so each platform gets its own top-level test even
* though that repeats a little.
   SUBROUTINE MVPKG.SH(SHCMD, SHOUT, SHSTAT)
$INCLUDE MVPKG.INC PLATFORM.H
   COMMON /MVPKGSH/ SHSEQ
   SHOUT = "" ; SHSTAT = -1
   IF TRIM(SHCMD) = "" THEN RETURN
* GETENV directly and NEVER the MVPKG.ENV seam: on UniVerse that seam reads the
* environment by running a command, which would come straight back here.  And
* UniVerse has no GETENV either, so there it is not asked at all -- a temp dir
* is not worth a fork, and /tmp is what TMPDIR would almost always say.
   SHTMP = "/tmp"
$IFDEF JBASE
   SHTMP = GETENV("TMPDIR") ; IF SHTMP = "" THEN SHTMP = "/tmp"
$ENDIF
$IFDEF UDT
   SHTMP = GETENV("TMPDIR") ; IF SHTMP = "" THEN SHTMP = "/tmp"
$ENDIF
$IFDEF MVX
   SHTMP = GETENV("TMPDIR") ; IF SHTMP = "" THEN SHTMP = "/tmp"
$ENDIF
   SHSEQ += 1
   SHBASE = SHTMP : "/mvpkgsh." : @USERNO : "." : SHSEQ
   SHF = SHBASE : ".sh"
   SHR = SHBASE : ".rc"
   SHSCRIPT = SHCMD
   SHSCRIPT<-1> = "echo $? > " : SHR
*
$IFDEF JBASE
   OSWRITE SHSCRIPT ON SHF
* THE REDIRECTION GOES IN THE SCRIPT, NOT ON THE EXECUTE LINE.  Writing
* EXECUTE "sh f > out 2>&1" hands jBASE the > and the 2>&1 as literal argv
* words, which is the problem this routine exists to solve.
   EXECUTE "sh " : SHF CAPTURING SHOUT
   OSREAD SHRC FROM SHR ELSE SHRC = ""
   CALL MVPKG.SH.RM(SHF, SHR)
$ENDIF
*
$IFDEF UV
* No OSWRITE here either, so the script is written with OPENSEQ/WRITESEQ.
* OPENSEQ on a path that does not exist yet fails; CREATE is what makes it.
   OPENSEQ SHF TO SHFV ELSE
      CREATE SHFV ELSE RETURN
   END
   SHN = DCOUNT(SHSCRIPT, @AM)
   FOR SHI = 1 TO SHN
      WRITESEQ SHSCRIPT<SHI> ON SHFV ELSE NULL
   NEXT SHI
   CLOSESEQ SHFV
   EXECUTE 'SH -c "sh ' : SHF : '"' CAPTURING SHOUT
   OPENSEQ SHR TO SHRV THEN
      READSEQ SHRC FROM SHRV ELSE SHRC = ""
      CLOSESEQ SHRV
   END ELSE SHRC = ""
   EXECUTE 'SH -c "rm -f ' : SHF : " " : SHR : '"' CAPTURING SHJUNK
$ENDIF
*
$IFDEF UDT
   EXECUTE '!' : SHCMD : ' ; echo $? > ' : SHR CAPTURING SHOUT
   OSREAD SHRC FROM SHR ELSE SHRC = ""
   EXECUTE '!rm -f ' : SHR CAPTURING SHJUNK
$ENDIF
*
$IFDEF MVX
   EXECUTE '!' : SHCMD : ' ; echo $? > ' : SHR CAPTURING SHOUT
   SHRC = OSREAD(SHR)
   IF STATUS() # 0 THEN SHRC = ""
   EXECUTE '!rm -f ' : SHR CAPTURING SHJUNK
$ENDIF
*
* echo leaves a newline and TRIM strips only spaces, so NUM() rejects "0" and
* every status reads as unknown unless the line is taken first.
   SHRC = TRIM(FIELD(SHRC, CHAR(10), 1))
   IF NUM(SHRC) AND SHRC # "" THEN SHSTAT = SHRC + 0
   RETURN

