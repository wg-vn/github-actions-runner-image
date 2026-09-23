#!/bin/bash
# Runs a job of deploy-production.yml locally with act, simulating a release
# for the next tag in line (minor bump, e.g. v1.8.0 -> v1.9.0), or for an
# explicit tag if one is given (e.g. v1.20.1 for a patch release). See
# act_release.sh for how the release event/GITHUB_REF are simulated.
#
# Usage: act-next-release.sh <build|deploy> [tag]
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ] || { [ "$1" != "build" ] && [ "$1" != "deploy" ]; }; then
  echo "Usage: $(basename "$0") <build|deploy> [tag]" >&2
  exit 1
fi

if [ $# -eq 2 ] && ! [[ "$2" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: tag must be in the form vMAJOR.MINOR.PATCH (e.g. v1.20.1), got '$2'." >&2
  exit 1
fi

case "$1" in
  build) ACTION_NAME="build-and-push" ;;
  deploy) ACTION_NAME="deploy" ;;
esac

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is not installed." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh (GitHub CLI) is not installed." >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not inside a git repository - run this from the target repo (e.g. vndash) so the latest tag can be extracted." >&2
  exit 1
fi

LATEST_TAG=$(git tag --sort=-v:refname | head -1)

if [ $# -eq 2 ]; then
  NEXT_TAG="$2"
else
  IFS='.' read -r MAJOR MINOR _ <<< "${LATEST_TAG#v}"
  NEXT_TAG="v${MAJOR}.$((MINOR + 1)).0"
fi

# act doesn't read the local git remote, so github.repository defaults to its
# own placeholder (nektos/act) unless GITHUB_REPOSITORY is passed in - without
# this, image builds push to ghcr.io/nektos/act/... and fail with
# permission_denied: create_package.
ORIGIN_URL=$(git remote get-url origin)
GITHUB_REPOSITORY=$(echo "$ORIGIN_URL" | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')

echo "Latest tag:      ${LATEST_TAG}"
echo "Next tag:        ${NEXT_TAG}"
echo "GitHub repository: ${GITHUB_REPOSITORY}"

if [ "$1" = "deploy" ]; then
  git tag "${NEXT_TAG}"
  git push origin "${NEXT_TAG}"
  RELEASE_URL=$(gh release create "${NEXT_TAG}" --title "${NEXT_TAG}" --generate-notes --latest)

  echo "Release ${NEXT_TAG} created and published as latest: ${RELEASE_URL}"

  read -r -p "Run the deploy job now? [y/N] " CONFIRM
  if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Aborted before running the deploy job."
    exit 0
  fi
fi

"$(dirname "$0")/act_release.sh" "${ACTION_NAME}" "${NEXT_TAG}" --env "GITHUB_REPOSITORY=${GITHUB_REPOSITORY}"
