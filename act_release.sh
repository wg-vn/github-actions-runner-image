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

cat > "$EVENT_FILE" <<EOF
{
  "action": "published",
  "release": {
    "tag_name": "${TAG}",
    "name": "${TAG}"
  }
}
EOF

act release -j "$ACTION_NAME" \
  -e "$EVENT_FILE" \
  --env GITHUB_REF="refs/tags/${TAG}" \
  "$@"
