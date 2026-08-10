* mv_package — MVPKG.MANIFEST record layout (UniData port).
* Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see LICENSE).
*
* MVPKG.MANIFEST — this account's DECLARED dependency set: the composer.json
* equivalent, and human-editable.  A native master-dictionary (VOC/MD) record,
* read/written only through the MVPKGOS MD* seam ops (never an OS file), so the
* account layer ports to D3/UniVerse.  Include with:  $INCLUDE BP MVPKG.MANIFEST.H
*
* Two forms of name are defined, by convention:
*   MANIFEST$FIELD — the plain attribute NUMBER; use in dynamic-array access,
*                    e.g.  REC<MANIFEST$DEPS>  or  REC<MANIFEST$DEPS, I>.
*   MANIFEST.FIELD — an alias to an element of the dimensioned array MANIFEST.REC
*                    (DIMd below); use in MAT code after  MATPARSE MANIFEST.REC
*                    FROM rec USING @AM  (or MATREAD).
*
*   field    #   holds
*   MARKER   1   "MVPKG-MANIFEST" — self-describing type marker
*   DEPS     2   multivalued: one declared dependency per value, each a spec
*                [?]name[@sys][:constraint]  (see DEPAPPLY):
*                  ?           leading — optional (install if available, skip
*                              without failing if not)
*                  @sys,sys    only those systems;  @!sys,sys  all but those
*                  :^1.2  :~1.0  :>=1.0,<2.0  :1.2.*  :1.2.3   a constraint
*                e.g.  mvx-lang/git   mvx-lang/curl:^1.0   ?mvx-lang/curses
*
   DIM MANIFEST.REC(2)
*  --- attribute numbers (dynamic array:  REC<MANIFEST$FIELD> ) ---
   EQUATE MANIFEST$MARKER TO 1
   EQUATE MANIFEST$DEPS   TO 2
*  --- dimensioned-array element aliases (MAT:  MANIFEST.REC ), subscripted by
*      the $ constants so the position lives in exactly one place ---
   EQUATE MANIFEST.MARKER TO MANIFEST.REC(MANIFEST$MARKER)
   EQUATE MANIFEST.DEPS   TO MANIFEST.REC(MANIFEST$DEPS)
