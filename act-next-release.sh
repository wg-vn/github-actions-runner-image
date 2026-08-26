#!/bin/bash
# Runs the build-and-push job of deploy-production.yml locally with act,
# simulating a release for the next tag in line (minor bump, e.g. v1.8.0 ->
# v1.9.0). See act_release.sh for how the release event/GITHUB_REF are simulated.
set -euo pipefail

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is not installed." >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not inside a git repository - run this from the target repo (e.g. vndash) so the latest tag can be extracted." >&2
  exit 1
fi

LATEST_TAG=$(git tag --sort=-v:refname | head -1)

IFS='.' read -r MAJOR MINOR _ <<< "${LATEST_TAG#v}"
NEXT_TAG="v${MAJOR}.$((MINOR + 1)).0"

echo "Latest tag: ${LATEST_TAG}"
echo "Next tag:   ${NEXT_TAG}"
"$(dirname "$0")/act_release.sh" build-and-push "${NEXT_TAG}"
