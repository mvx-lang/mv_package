      FAIL = 0 ; N = 0
* ---- RANK is strict: only the five stability words score --------------
      GOSUB RANKS
* ---- SAT with no floor keeps the old Composer rule --------------------
      GOSUB SATC1
* ---- a branch dev version is the top of its branch (mvx#364) ----------
      GOSUB BRANCHDEV
      IF FAIL = 0 THEN PRINT N : " checks, ALL PASS" ELSE PRINT FAIL : " of " : N : " FAILED"
      STOP

RANKS:
      CASES = "stable:5 rc:4 beta:3 alpha:2 dev:1 STABLE:5 Beta:3"
      CASES := " main:0 dev-branch:0 1.2.3:0 feature/x:0 v2:0 :0"
      FOR I = 1 TO DCOUNT(CASES, " ")
         ONE = FIELD(CASES, " ", I)
         IF ONE # "" THEN
            WD = FIELD(ONE, ":", 1) ; EXP = FIELD(ONE, ":", 2)
            CALL SEMVER("RANK", WD, "", GOT)
            LBL = "RANK " : WD
            GOSUB CHECK
         END
      NEXT I
      RETURN

SATC1:
*     ver | constraint | expected
      T = ""
      T<-1> = "1.2.0:^1.0:1"
      T<-1> = "1.2.0-beta1:^1.0:0"
      T<-1> = "1.2.0-beta1:^1.0-beta:1"
      T<-1> = "1.2.0-beta1:^1.0@beta:1"
      T<-1> = "1.2.0-alpha1:^1.0@beta:0"
      T<-1> = "1.2.0-rc1:^1.0@beta:1"
      T<-1> = "1.2.0-dev:^1.0@dev:1"
      T<-1> = "1.2.0-beta1:^1.0@stable:0"
      T<-1> = "1.2.0:^1.0@beta:1"
      T<-1> = "1.2.0-beta1:@beta:1"
      T<-1> = "1.2.0-beta1::0"
      T<-1> = "1.2.0-beta1:*@beta:1"
      T<-1> = "1.2.0-beta1:*:0"
      T<-1> = "1.2.0:*:1"
      T<-1> = "2.0.0-rc1:^1.0@dev:0"
      T<-1> = "1.9.0-rc1:>=1.5@rc:1"
      T<-1> = "1.9.0-beta1:>=1.5@rc:0"
      T<-1> = "1.2.0-beta1:^1.0@bogus:0"
      T<-1> = "1.0.0-beta1:^1.0@beta:1"
      T<-1> = "1.0.0-alpha1:^1.0.0-beta1@alpha:0"
      T<-1> = "1.0.0-rc1:^1.0.0-beta1@alpha:1"
      T<-1> = "2.0.0-dev:^1.0@dev:0"
      T<-1> = "1.4.9-beta1:~1.4@beta:1"
      T<-1> = "1.5.0-beta1:~1.4@beta:0"
      T<-1> = "1.2.3-beta1:1.2.*@beta:1"
      T<-1> = "1.3.0-beta1:1.2.*@beta:0"
      T<-1> = "0.9.0-beta1:^1.0@beta:0"
*     the stable-only rules, unchanged by the floor work
      T<-1> = "1.0.0:^1.0:1"
      T<-1> = "1.9.9:^1.0:1"
      T<-1> = "2.0.0:^1.0:0"
      T<-1> = "0.9.9:^1.0:0"
      T<-1> = "1.4.5:~1.4:1"
      T<-1> = "1.5.0:~1.4:0"
      T<-1> = "0.5.9:^0.5:1"
      T<-1> = "0.6.0:^0.5:0"
      T<-1> = "1.2.3:1.2.3:1"
      T<-1> = "1.2.4:1.2.3:0"
      T<-1> = "1.2.3:>=1.0:1"
      T<-1> = "1.2.3:<1.0:0"
      T<-1> = "1.2.9:1.2.*:1"
      FOR I = 1 TO DCOUNT(T, @AM)
         VV = FIELD(T<I>, ":", 1) ; CC = FIELD(T<I>, ":", 2) ; EXP = FIELD(T<I>, ":", 3)
         CALL SEMVER("SAT", VV, CC, GOT)
         LBL = "SAT " : VV : " / " : CC
         GOSUB CHECK
      NEXT I
      RETURN

BRANCHDEV:
* Composer's 1.4.x-dev: NOT a pre-release of one patch but every unreleased
* commit on that line, so it sorts ABOVE every release on the branch and BELOW
* the next one up.  The tag the nightly moves used to be a bare "dev", which
* PARSE read as 0.0.0 with no pre-release -- a STABLE version zero.
*     ver | other | expected CMP
      T = ""
      T<-1> = "1.4.x-dev":@VM:"1.4.0":@VM:"1"
      T<-1> = "1.4.x-dev":@VM:"1.4.99":@VM:"1"
      T<-1> = "1.4.x-dev":@VM:"1.5.0":@VM:"-1"
      T<-1> = "1.4.x-dev":@VM:"1.4.0-beta.1":@VM:"1"
      T<-1> = "1.x-dev":@VM:"1.99.99":@VM:"1"
      T<-1> = "1.x-dev":@VM:"2.0.0":@VM:"-1"
*     and the shape that reads the wrong way round, kept as a case: a
*     pre-release sorts BELOW its own version, so <current>-dev would claim to
*     predate the release it was built after.
      T<-1> = "1.4.0-dev":@VM:"1.4.0":@VM:"-1"
      FOR I = 1 TO DCOUNT(T, @AM)
         V1 = T<I,1> ; V2 = T<I,2> ; EXP = T<I,3>
         CALL SEMVER("CMP", V1, V2, GOT)
         LBL = "CMP " : V1 : " " : V2
         GOSUB CHECK
      NEXT I
* It is a dev build, by the stability ladder, not a stable one.
      CALL SEMVER("STABILITY", "1.4.x-dev", "", GOT)
      EXP = "dev" ; LBL = "STABILITY 1.4.x-dev" ; GOSUB CHECK
*
* AND A BARE CONSTRAINT STILL EXCLUDES IT.  A branch dev version is a
* pre-release, so `MVPKG install <pkg>` with no constraint must not pick it.
      CALL SEMVER("SAT", "1.4.x-dev", "", GOT)
      EXP = 0 ; LBL = "SAT 1.4.x-dev (no constraint)" ; GOSUB CHECK
      CALL SEMVER("SAT", "1.4.x-dev", "*", GOT)
      EXP = 0 ; LBL = "SAT 1.4.x-dev (*)" ; GOSUB CHECK
*
* THE x IS ONLY A BRANCH MARKER WITH A SUFFIX, so constraints are untouched:
* 1.4.* and 1.4.x mean "any 1.4 release", the other end of the range.  If the
* suffix were not required, 1.4.0 would stop satisfying them -- the sentinel
* would have made the constraint mean 1.4.9999999.
      CALL SEMVER("SAT", "1.4.0", "1.4.*", GOT)
      EXP = 1 ; LBL = "SAT 1.4.0 against 1.4.*" ; GOSUB CHECK
      CALL SEMVER("SAT", "1.4.0", "1.4.x", GOT)
      EXP = 1 ; LBL = "SAT 1.4.0 against 1.4.x" ; GOSUB CHECK
      RETURN

CHECK:
      N = N + 1
      IF GOT # EXP THEN
         FAIL = FAIL + 1
         PRINT "FAIL  " : LBL : "  expected " : EXP : " got " : GOT
      END
      RETURN
