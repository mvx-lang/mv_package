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
*                  @beta       a stability floor for this one dependency, on
*                              the name or after the constraint ("x:^1.2@beta")
*                e.g.  mvx-lang/git   mvx-lang/curl:^1.0   ?mvx-lang/curses
*   MINSTAB  3   minimum-stability: the least stable build this project accepts
*                (dev|alpha|beta|rc|stable).  Empty means stable, which is what
*                every account resolved at before this existed.            [#30]
*   PREFSTAB 4   prefer-stable: "1" turns it ON.  OFF by default (as in
*                Composer): the newest admissible version wins outright, which
*                is why `install thing@beta` gets the beta.  On, a package takes
*                the newest STABLE version satisfying its constraint and drops
*                to a pre-release only when nothing stable does.  At a floor of
*                stable the setting has nothing to decide.                 [#30]
*
* THE POLICY LIVES WITH THE DEPENDENCIES, not in client config, because it is a
* property of the PROJECT: a checkout that carries its manifest carries the
* floor its dependencies were resolved under.
*
   DIM MANIFEST.REC(4)
*  --- attribute numbers (dynamic array:  REC<MANIFEST$FIELD> ) ---
   EQUATE MANIFEST$MARKER TO 1
   EQUATE MANIFEST$DEPS   TO 2
   EQUATE MANIFEST$MINSTAB  TO 3
   EQUATE MANIFEST$PREFSTAB TO 4
*  --- dimensioned-array element aliases (MAT:  MANIFEST.REC ), subscripted by
*      the $ constants so the position lives in exactly one place ---
   EQUATE MANIFEST.MARKER TO MANIFEST.REC(MANIFEST$MARKER)
   EQUATE MANIFEST.DEPS   TO MANIFEST.REC(MANIFEST$DEPS)
   EQUATE MANIFEST.MINSTAB  TO MANIFEST.REC(MANIFEST$MINSTAB)
   EQUATE MANIFEST.PREFSTAB TO MANIFEST.REC(MANIFEST$PREFSTAB)
