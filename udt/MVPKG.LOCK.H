* mv_package — MVPKG.LOCK record layout (UniData port).
* Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see LICENSE).
*
* MVPKG.LOCK — this account's RESOLVED / installed set: the composer.lock
* equivalent, and the record MVPKG.HAS / MVPKG.LIST read for deployed status.
* A native master-dictionary (VOC/MD) record (never an OS file), written by
* install / register / remove through the MVPKGOS MD* seam ops.  It replaces the
* old OS-level mvpkg.installed manifest.  Include with:  $INCLUDE BP MVPKG.LOCK.H
*
* Attributes <2>..<6> are PARALLEL multivalues — one value position per package,
* so LOCK.VERSIONS<...,i> is the version of LOCK.NAMES<...,i>, and so on.
*
* Two forms of name are defined, by convention:
*   LOCK$FIELD  — the plain attribute NUMBER; use in dynamic-array access, e.g.
*                 REC<LOCK$NAMES>  or  REC<LOCK$VERSIONS, I>.
*   LOCK.FIELD  — an alias to an element of the dimensioned array LOCK.REC (DIMd
*                 below); use in MAT code after  MATPARSE LOCK.REC FROM rec USING
*                 @AM  (or MATREAD), e.g.  LOCK.NAMES = "...".
*
*   field       #   holds
*   MARKER      1   "MVPKG-LOCK" — self-describing type marker
*   NAMES       2   package names, plus the virtual names a package provides
*   VERSIONS    3   resolved version:  <semver> released | "" a provided name |
*                                      "source" a --source (git working copy)
*   SOURCE      4   origin:  "" released | "git" (git-ref install; reserved, #23)
*   REF         5   git ref (dev/branch/tag) an install came from ("")   [#23]
*   COMMIT      6   resolved commit SHA of a git install ("")            [#23]
*   FOOTPRINT   7   the account artifacts THIS install deployed here, pinned so
*                   REMOVE/UPDATE reverse exactly what was laid down — never
*                   what a later manifest happens to say.  One VM per package
*                   (parallel to NAMES); within it an @SM list of artifacts,
*                   each "<KIND> <arg>":  "V <verb>" a VOC verb pointer,
*                   "F <name>:<type>" a deployed account file (recorded, not
*                   auto-removed — files hold data).  Empty on MVX, where the
*                   whole package is linked/unlinked as a unit.             [#33]
*   STABILITY   8   the resolved version's stability (dev|alpha|beta|rc|stable),
*                   parallel to NAMES.  Recorded so a reader can see WHAT KIND
*                   of build is pinned without re-deriving it from the version
*                   string, and so a since-raised minimum-stability can point at
*                   the pins it would no longer choose.  Empty for a provided
*                   name and for a source working copy — neither is a release.
*                   NOT <4>: that is SOURCE, reserved for the git-ref install.
*                                                                          [#30]
*
   DIM LOCK.REC(8)
*  --- attribute numbers (dynamic array:  REC<LOCK$FIELD> ) ---
   EQUATE LOCK$MARKER    TO 1
   EQUATE LOCK$NAMES     TO 2
   EQUATE LOCK$VERSIONS  TO 3
   EQUATE LOCK$SOURCE    TO 4
   EQUATE LOCK$REF       TO 5
   EQUATE LOCK$COMMIT    TO 6
   EQUATE LOCK$FOOTPRINT TO 7
   EQUATE LOCK$STABILITY TO 8
*  --- dimensioned-array element aliases (MAT:  LOCK.REC ), subscripted by the
*      $ constants so the position lives in exactly one place ---
   EQUATE LOCK.MARKER    TO LOCK.REC(LOCK$MARKER)
   EQUATE LOCK.NAMES     TO LOCK.REC(LOCK$NAMES)
   EQUATE LOCK.VERSIONS  TO LOCK.REC(LOCK$VERSIONS)
   EQUATE LOCK.SOURCE    TO LOCK.REC(LOCK$SOURCE)
   EQUATE LOCK.REF       TO LOCK.REC(LOCK$REF)
   EQUATE LOCK.COMMIT    TO LOCK.REC(LOCK$COMMIT)
   EQUATE LOCK.FOOTPRINT TO LOCK.REC(LOCK$FOOTPRINT)
   EQUATE LOCK.STABILITY TO LOCK.REC(LOCK$STABILITY)
