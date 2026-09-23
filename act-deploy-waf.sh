#!/bin/bash
# Triggers deploy-waf.yml's workflow_dispatch event locally with act. Unlike
# act_release.sh, no event payload is needed here - workflow_dispatch takes
# no inputs - so this just wires up the job name and the .act.secrets/
# .act.vars files deploy-waf.yml reads.
#
# Precondition: the vndash app containers (frontend/backend/redis/reverb)
# must already be deployed and running on the target host - deploy-waf.yml
# joins them to the waf-vndash-shared network but doesn't start them itself.
#
# Run from the target repo (vndash) so .github/workflows/deploy-waf.yml and
# .act.secrets/.act.vars are found; this script only needs its own location
# for its own file, not the repo's.
#
# Usage: act-deploy-waf.sh [extra act args...]
set -euo pipefail

if [ ! -f .github/workflows/deploy-waf.yml ]; then
  echo "Error: .github/workflows/deploy-waf.yml not found - run this from the vndash repo root." >&2
  exit 1
fi

echo "Running 'act workflow_dispatch' on $(pwd)..."

act workflow_dispatch -W .github/workflows/deploy-waf.yml \
  -j deploy \
  --secret-file .act.secrets --var-file .act.vars \
  "$@"
