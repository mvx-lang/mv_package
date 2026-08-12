* mv_package — MVPKG.CONF record layout (UniData port).
* Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see LICENSE).
*
* MVPKG.CONF — this account's per-account deploy configuration, set once by
* MVPKG init and read by the deploy seam (MVPKGOS) so REMOVE / UPDATE reverse
* with the SAME catalog scope + store the install used.  A native master-
* dictionary (VOC/MD) record.  Include with:  $INCLUDE BP MVPKG.CONF.H
*
* The two axes together make a "test environment" — a mvpkg install that runs
* alongside a live one on the same host without colliding (mv_package#34):
*
*   field    #   holds
*   MARKER   1   "MVPKG-CONF" — self-describing type marker
*   SCOPE    2   catalog scope:  "global" (default) globally cataloged in
*                $UDTHOME/sys/CTLG, shared by every account | "local" cataloged
*                LOCAL in this account only, so a test build does not overwrite
*                the live global catalog
*   PREFIX   3   account-name prefix ("" default | e.g. "test-"): namespaces the
*                store this env owns/references ($UDTHOME/<prefix>mvpkg) so a test
*                install keeps a store separate from the live one
*
* Catalog scope is a UniData concern (MVX links whole packages into the account
* — no shared catalog, no Q-pointers), so this record + its EQUATEs live here in
* the udt port only.
*
   DIM CONF.REC(3)
*  --- attribute numbers (dynamic array:  REC<CONF$FIELD> ) ---
   EQUATE CONF$MARKER TO 1
   EQUATE CONF$SCOPE  TO 2
   EQUATE CONF$PREFIX TO 3
*  --- dimensioned-array element aliases (MAT:  CONF.REC ) ---
   EQUATE CONF.MARKER TO CONF.REC(CONF$MARKER)
   EQUATE CONF.SCOPE  TO CONF.REC(CONF$SCOPE)
   EQUATE CONF.PREFIX TO CONF.REC(CONF$PREFIX)
