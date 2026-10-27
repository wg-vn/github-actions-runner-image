#!/bin/bash
# Runs a vndash release (build-and-push, then deploy) with act ON the
# production server instead of this machine, so the image builds and pushes use
# the server's network and not this one's (e.g. when tethered to a phone). Use
# it when GitHub Actions is unavailable and act-next-release.sh would be too
# heavy locally. The release and tag must already exist (act-next-release.sh
# creates them before it asks to run the job).
#
# What it does, over `tailscale ssh`:
#   1. uploads this machine's act binary, a shallow clone of the tag,
#      .act.secrets/.act.vars (mode 600) and the real release event payload
#      into ~/act-release on the server;
#   2. starts act detached, plus a guard that stops act's buildkit container if
#      the server's available memory falls below MEMGUARD_MB (a cold Nuxt build
#      pushed ~4G into swap on the 15G host; production shares it);
#   3. follows the step results until act exits, then deletes everything it
#      uploaded.
# If the connection drops the run keeps going and nothing is deleted; the
# commands to re-attach and to clean up are printed.
#
# The Tailscale step in deploy-production.yml needs /dev/net/tun and NET_ADMIN
# in the job container (it runs tailscaled); stock act containers have neither,
# so they are added with --container-options instead of --privileged.
#
# Run from the vndash repo root (needs .act.secrets and .act.vars).
#
# Usage: act-release-on-server.sh [--check] <tag>
#        act-release-on-server.sh cleanup
#   --check   run the local and server preflight checks only
#   cleanup   remove ~/act-release and act's leftovers from the server
#
# Environment: ACT_SERVER (default wgarcia@phonemgr), MEMGUARD_MB (default 1024)
set -euo pipefail

SERVER="${ACT_SERVER:-wgarcia@phonemgr}"
MEMGUARD_MB="${MEMGUARD_MB:-1024}"
RUNNER_IMAGE="catthehacker/ubuntu:act-24.04"
SSH=(tailscale ssh "$SERVER")

cleanup_server() {
  "${SSH[@]}" "rm -rf ~/act-release ~/.config/act ~/.cache/act
    docker ps -aq --filter name=act-CI-CD | xargs -r docker rm -f >/dev/null
    docker rmi $RUNNER_IMAGE >/dev/null 2>&1 || true"
}

if [ "${1:-}" = "cleanup" ]; then
  cleanup_server
  echo "Removed ~/act-release and act leftovers from ${SERVER}."
  exit 0
fi

CHECK_ONLY=false
if [ "${1:-}" = "--check" ]; then
  CHECK_ONLY=true
  shift
fi

if [ $# -ne 1 ] || ! [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $(basename "$0") [--check] <tag>   (tag like v1.39.0)" >&2
  echo "       $(basename "$0") cleanup" >&2
  exit 1
fi
TAG="$1"

for tool in tailscale git gh act gzip; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Error: $tool is not installed." >&2; exit 1; }
done

if [ ! -f .github/workflows/deploy-production.yml ] || [ ! -f .act.secrets ] || [ ! -f .act.vars ]; then
  echo "Error: run this from the vndash repo root (needs .github/workflows/deploy-production.yml, .act.secrets, .act.vars)." >&2
  exit 1
fi

git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null || { echo "Error: tag ${TAG} does not exist locally." >&2; exit 1; }

# Same derivation as act-next-release.sh: act does not read the git remote.
ORIGIN_URL=$(git remote get-url origin)
GITHUB_REPOSITORY=$(echo "$ORIGIN_URL" | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')

EVENT_FILE=$(mktemp)
CLONE_DIR=$(mktemp -d)
trap 'rm -rf "$EVENT_FILE" "$CLONE_DIR"' EXIT

# Unlike act_release.sh there is no fallback: the Google Chat step needs the
# real release, and a deploy without a release is not what this script is for.
gh api "repos/{owner}/{repo}/releases/tags/${TAG}" \
  --jq '{action: "published", release: .}' > "$EVENT_FILE" \
  || { echo "Error: no GitHub release for ${TAG}." >&2; exit 1; }

echo "Checking ${SERVER}..."
# shellcheck disable=SC2016  # $ expands on the server, not here
REMOTE_STATE=$("${SSH[@]}" 'echo "arch=$(uname -m)"; command -v docker >/dev/null && echo docker=yes || echo docker=no
  [ -e ~/act-release ] && echo leftover=yes || echo leftover=no
  echo "mem_mb=$(awk "/MemAvailable/ {print int(\$2/1024)}" /proc/meminfo)"
  echo "swap_used_mb=$(free -m | awk "/Swap/ {print \$3}")"')
# shellcheck disable=SC2001  # indents every line, not a single substitution
echo "$REMOTE_STATE" | sed 's/^/  /'
remote() { echo "$REMOTE_STATE" | sed -n "s/^$1=//p"; }

[ "$(remote arch)" = "$(uname -m)" ] || { echo "Error: server arch $(remote arch) differs from this machine's $(uname -m); the local act binary would not run there." >&2; exit 1; }
[ "$(remote docker)" = "yes" ] || { echo "Error: docker not available to ${SERVER}." >&2; exit 1; }
if [ "$(remote leftover)" = "yes" ]; then
  echo "Error: ~/act-release already exists on ${SERVER} (a run in progress, or one that was not cleaned up). Inspect it, or run: $(basename "$0") cleanup" >&2
  exit 1
fi
if [ "$(remote mem_mb)" -lt $((MEMGUARD_MB * 3)) ]; then
  echo "WARNING: only $(remote mem_mb) MB available on the server (guard stops the build below ${MEMGUARD_MB} MB)." >&2
fi

if [ "$CHECK_ONLY" = true ]; then
  echo "Preflight OK for ${TAG} on ${SERVER}."
  exit 0
fi

echo
echo "Release:  ${TAG} (${GITHUB_REPOSITORY})"
echo "Server:   ${SERVER}"
echo "This pushes ${TAG} (and latest) images to ghcr and restarts the PRODUCTION stack on ${SERVER}."
read -r -p "Run build-and-push + deploy on the server now? [y/N] " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo "Aborted."
  exit 1
fi

git clone -q --depth 1 --branch "$TAG" "file://$(pwd)" "$CLONE_DIR/vn-dashboard" 2>/dev/null
git -C "$CLONE_DIR/vn-dashboard" remote set-url origin "$ORIGIN_URL"

echo "Uploading to ${SERVER}:~/act-release (act binary, repo at ${TAG}, secrets, event)..."
"${SSH[@]}" 'mkdir -p -m 700 ~/act-release ~/.config/act'
tar -C "$CLONE_DIR" -czf - vn-dashboard | "${SSH[@]}" 'tar -xzf - -C ~/act-release'
gzip -c "$(command -v act)" | "${SSH[@]}" 'gunzip > ~/act-release/act && chmod 755 ~/act-release/act'
"${SSH[@]}" 'umask 077; cat > ~/act-release/vn-dashboard/.act.secrets' < .act.secrets
"${SSH[@]}" 'umask 077; cat > ~/act-release/vn-dashboard/.act.vars' < .act.vars
"${SSH[@]}" 'cat > ~/act-release/event.json' < "$EVENT_FILE"
"${SSH[@]}" "cat > ~/.config/act/actrc" <<EOF
-P ubuntu-24.04=${RUNNER_IMAGE}
--network bridge
--secret-file=.act.secrets
--var-file=.act.vars
EOF

"${SSH[@]}" "cat > ~/act-release/memguard.sh && chmod 700 ~/act-release/memguard.sh" <<EOF
#!/bin/bash
# Stops act's buildkit container if available memory drops below the limit.
# Exits when the act process (pid in act.pid) is gone.
cd ~/act-release
while kill -0 "\$(cat act.pid)" 2>/dev/null; do
  avail=\$(awk '/MemAvailable/ {print int(\$2/1024)}' /proc/meminfo)
  if [ "\$avail" -lt ${MEMGUARD_MB} ]; then
    echo "\$(date -u +%FT%TZ) GUARD TRIPPED: \${avail}MB available, stopping buildkit" | tee -a guard.log
    docker ps -q --filter name=buildx_buildkit | xargs -r docker stop
    exit 0
  fi
  sleep 3
done
EOF

echo "Starting act on the server..."
"${SSH[@]}" "cd ~/act-release && touch run.log guard.log && cd vn-dashboard &&
  TAG=${TAG} REPO=${GITHUB_REPOSITORY} setsid nohup bash -c '../act release -j deploy -e ../event.json \
    --env GITHUB_REF=refs/tags/\$TAG --env GITHUB_REPOSITORY=\$REPO \
    --container-options \"--cap-add=NET_ADMIN --cap-add=NET_RAW --device /dev/net/tun\" \
    > ../run.log 2>&1; echo \$? > ../act.exit' >/dev/null 2>&1 </dev/null &
  echo \$! > ~/act-release/act.pid
  cd ~/act-release && setsid nohup ./memguard.sh >/dev/null 2>&1 </dev/null &"

FOLLOW="cd ~/act-release && tail -n 0 -F --pid=\$(cat act.pid) run.log guard.log 2>/dev/null"
echo "Following step results (full log: ${SERVER}:~/act-release/run.log)..."
"${SSH[@]}" "$FOLLOW" \
  | sed -E --unbuffered 's/\x1b\[[0-9;]*m//g' \
  | grep -E --line-buffered 'Run (Main|Post)|✅|❌|🏁|::error|GUARD|failed to solve|\| ERROR|unauthorized|denied' || true

# tail ends when act exits, but also when the connection drops.
if ! "${SSH[@]}" '[ -e ~/act-release/act.exit ]'; then
  echo >&2
  echo "Lost the connection, or act is still running; the run continues on the server and nothing was deleted." >&2
  echo "  follow:  tailscale ssh ${SERVER} 'tail -f ~/act-release/run.log'" >&2
  echo "  cleanup (after it finishes): $(basename "$0") cleanup" >&2
  exit 2
fi

EXIT_CODE=$("${SSH[@]}" 'cat ~/act-release/act.exit')
if [ "$EXIT_CODE" = "0" ]; then
  cleanup_server
  echo "Deploy of ${TAG} succeeded; server cleaned up."
else
  echo "act exited with ${EXIT_CODE}; the log and files are kept on the server for inspection." >&2
  echo "  log:     tailscale ssh ${SERVER} 'tail -200 ~/act-release/run.log'" >&2
  echo "  cleanup: $(basename "$0") cleanup" >&2
  exit "$EXIT_CODE"
fi
