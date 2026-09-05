# version.sh — one version string for every build script.  Sourced, not run.
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see LICENSE).
#
#   mvpkg_version [source-dir]
#
# A release carries its version and nothing else: a tag is a promise that the
# name identifies the tree, so 1.17.0 stays 1.17.0.  A dev build cannot make
# that promise, so it carries the short commit too (1.17.0-beta4+g4579f6b) --
# a bug reported against a bare "1.17.0-beta4" that is really several commits
# past the tag costs an afternoon to work out.
#
# A version handed in through $MVPKG_VERSION or $GITHUB_REF_NAME is taken as a
# release stamp and used verbatim -- that is how the release workflow passes the
# tag, and how a source tarball (no .git at all) still gets a real version.
mvpkg_version() {
    _d="${1:-$(dirname "$0")}"

    _v="${MVPKG_VERSION:-${GITHUB_REF_NAME:-}}"
    if [ -n "$_v" ]; then printf '%s' "$_v"; return 0; fi

    if ! git -C "$_d" rev-parse --git-dir >/dev/null 2>&1; then
        printf '0'; return 0
    fi
    if _t=$(git -C "$_d" describe --exact-match --tags HEAD 2>/dev/null); then
        printf '%s' "$_t"; return 0          # sitting on a tag: the tag alone
    fi
    _v=$(git -C "$_d" describe --tags --abbrev=0 2>/dev/null) || _v=0
    _h=$(git -C "$_d" rev-parse --short HEAD 2>/dev/null) || _h=
    if [ -n "$_h" ]; then printf '%s+g%s' "$_v" "$_h"; else printf '%s' "$_v"; fi
}

# mvpkg_stamp_manifests <staged-dir> <version>
#
# Write the release's version into the PKG and mvpkg.json it ships.
#
# THESE TWO ARE NOT DECORATION.  The registry reads them, and mvpkg REGISTERS
# ITSELF from PKG line 2 -- so a manifest left behind by the tag makes the
# package manager install one version and then report another:
#
#     installed  mvpkg 1.17.0-beta4       (the tag, via the registry)
#     registered mvx-lang/mvpkg 1.16.0    (PKG line 2, months stale)
#
# Keeping them in step by hand does not work; mv_git shipped 2.0.0 declaring
# itself 2.0.0-rc5 doing exactly that.  So the manifests take the same source of
# truth as everything else rather than a second one that has to be remembered.
#
# In-tree PKG/mvpkg.json are now only a default for a dev build.  A release
# stamps over them.
mvpkg_stamp_manifests() {
    _dir="$1"; _ver="$2"
    [ -n "$_dir" ] && [ -n "$_ver" ] || return 0

    if [ -f "$_dir/PKG" ]; then
        # line 2 is the version (line 1 name, 3 description, 4 systems)
        awk -v v="$_ver" 'NR==2 {print v; next} {print}' "$_dir/PKG" > "$_dir/PKG.$$" \
            && mv "$_dir/PKG.$$" "$_dir/PKG"
    fi
    if [ -f "$_dir/mvpkg.json" ]; then
        sed 's/^\([[:space:]]*"version"[[:space:]]*:[[:space:]]*\)"[^"]*"/\1"'"$_ver"'"/' \
            "$_dir/mvpkg.json" > "$_dir/mvpkg.json.$$" \
            && mv "$_dir/mvpkg.json.$$" "$_dir/mvpkg.json"
    fi
    printf 'stamped manifests: %s\n' "$_ver"
}
