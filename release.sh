#!/bin/sh
# Tag and push a paired release: v<upstream-version> on the source
# branch, debian/<full-version> on the packaging branch. Both tag
# names derive from debian/changelog on the packaging branch tip.
# The packaging-tag push triggers .github/workflows/release.yml.
# See "Releasing" in debian/source/README.source.
#
# Usage: ./release.sh [--execute]   (no args = dry run)
set -eu

REMOTE=origin
SRC_BRANCH=main
PKG_BRANCH=debian/latest

# Default to a dry run. Tagging and pushing require an explicit --execute.
DRY=1
case "${1:-}" in
	--execute) DRY=0 ;;
	--dry-run|'') DRY=1 ;;
	*) echo "usage: $0 [--execute]   (no args = dry run)" >&2; exit 2 ;;
esac

git fetch --tags --quiet "$REMOTE"

# Read the changelog from the remote packaging tip, not the working
# tree. The tag must name the version of the commit it points at.
FULL=$(git show "${REMOTE}/${PKG_BRANCH}:debian/changelog" \
	| dpkg-parsechangelog -l- -SVersion)
# Strip any epoch. Colons are illegal in git refs, so no tag carries one.
TAG_VER=${FULL#*:}
UPSTREAM=${TAG_VER%-*}
SRC_TAG="v${UPSTREAM}"
PKG_TAG="debian/${TAG_VER}"
PKG_SHA=$(git rev-parse "${REMOTE}/${PKG_BRANCH}")

# Reuse the source tag across packaging-only rebuilds (-2, -3). Keep an
# existing tag's target, otherwise tag the source tip.
CREATE_SRC=1
if SRC_SHA=$(git rev-parse -q --verify "refs/tags/${SRC_TAG}^{commit}"); then
	CREATE_SRC=0
	SRC_NOTE="existing tag, reused"
else
	SRC_SHA=$(git rev-parse "${REMOTE}/${SRC_BRANCH}")
	SRC_NOTE="new tag on ${REMOTE}/${SRC_BRANCH}"
fi

# A pre-existing packaging tag pointing elsewhere means the release
# was already cut from a different commit. Never silently retag.
if EXISTING=$(git rev-parse -q --verify "refs/tags/${PKG_TAG}^{commit}"); then
	if [ "$EXISTING" != "$PKG_SHA" ]; then
		echo "ERROR: ${PKG_TAG} exists at ${EXISTING}," >&2
		echo "       but ${REMOTE}/${PKG_BRANCH} is at ${PKG_SHA}." >&2
		echo "       Bump the changelog revision for a new release." >&2
		exit 1
	fi
fi

REPO=$(git remote get-url "$REMOTE" \
	| sed -E 's#(git@|https://)github\.com[:/]##; s#\.git$##')

echo "Release:       ${FULL}"
echo "Source tag:    ${SRC_TAG} -> ${SRC_SHA} (${SRC_NOTE})"
echo "Packaging tag: ${PKG_TAG} -> ${PKG_SHA} (${REMOTE}/${PKG_BRANCH})"

# Block unless the packaging tip is CI-green. An unreachable API blocks
# too. Releasing blind is as risky as releasing red.
BRANCH_ENC=$(printf %s "$PKG_BRANCH" | sed 's#/#%2F#g')
CONCLUSION=$(curl -sf --max-time 10 \
	"https://api.github.com/repos/${REPO}/actions/runs?branch=${BRANCH_ENC}&per_page=1" \
	2>/dev/null \
	| python3 -c 'import json,sys
r = json.load(sys.stdin)["workflow_runs"]
print(r[0]["conclusion"] or "in_progress" if r else "none")' \
	2>/dev/null) || CONCLUSION=unknown
if [ "$CONCLUSION" != "success" ]; then
	echo "ERROR: latest CI on ${PKG_BRANCH} is '${CONCLUSION}', not 'success'." >&2
	echo "       Wait for a green run on the packaging tip." >&2
	exit 1
fi

if [ "$DRY" -eq 1 ]; then
	echo "Dry run - no tags created, nothing pushed."
	echo "Re-run with --execute to create and push the tags."
	exit 0
fi

printf "Proceed? [y/N] "
read -r ANSWER
case "$ANSWER" in
	y|Y) ;;
	*) echo "Aborted."; exit 1 ;;
esac

if [ "$CREATE_SRC" -eq 1 ]; then
	git tag -a "$SRC_TAG" "$SRC_SHA" -m "ar0822-rpi-dkms ${UPSTREAM}"
fi
git rev-parse -q --verify "refs/tags/${PKG_TAG}" >/dev/null \
	|| git tag -a "$PKG_TAG" "$PKG_SHA" -m "ar0822-rpi-dkms Debian release ${FULL}"

# Atomic: both refs land or neither does, so release.yml's preflight
# can never fire without its paired source tag.
git push --atomic "$REMOTE" "refs/tags/${SRC_TAG}" "refs/tags/${PKG_TAG}"
echo "Pushed. Watch the release at: https://github.com/${REPO}/actions"
