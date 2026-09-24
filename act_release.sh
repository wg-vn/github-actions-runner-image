#!/bin/bash
# Simulates a GitHub "release: published" event with act, since act derives
# GITHUB_REF from the local checkout rather than the event payload — without
# this, GITHUB_REF stays refs/heads/<branch> and any step that expects a tag
# (e.g. deriving a version from refs/tags/*) breaks.
#
# Run from the target repo (the one whose .github/workflows you're testing);
# this script only needs its own location for its own file, not the repo's.
#
# Usage: act_release.sh <ACTION_NAME> <TAG> [extra act args...]
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $(basename "$0") <ACTION_NAME> <TAG> [extra act args...]" >&2
  echo "  ACTION_NAME  the -j job name to run" >&2
  echo "  TAG          the release tag to simulate, e.g. v1.9.0" >&2
  exit 1
fi

ACTION_NAME="$1"
TAG="$2"
shift 2

EVENT_FILE=$(mktemp)
trap 'rm -f "$EVENT_FILE"' EXIT

# Use the real release object when it exists, so steps reading html_url, body
# or prerelease (e.g. the Google Chat notification) get the same values as on
# GitHub. A build-only run can precede the release, so fall back to the tag.
if ! gh api "repos/{owner}/{repo}/releases/tags/${TAG}" \
  --jq '{action: "published", release: .}' > "$EVENT_FILE" 2>/dev/null; then
  echo "No GitHub release for ${TAG} yet; simulating one with only tag_name/name." >&2
  cat > "$EVENT_FILE" <<EOF
{
  "action": "published",
  "release": {
    "tag_name": "${TAG}",
    "name": "${TAG}",
    "prerelease": false
  }
}
EOF
fi

echo "Running 'act release' on `pwd`..."

act release -j "$ACTION_NAME" \
  -e "$EVENT_FILE" \
  --env GITHUB_REF="refs/tags/${TAG}" \
  "$@"
