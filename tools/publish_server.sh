#!/usr/bin/env bash
# Exports the headless Linux server program and publishes it as the latest
# GitHub release asset "8ber-server.x86_64". The Scareathon server downloads it
# from there (releases/latest/download/...) to host co-op rooms, re-checking for
# a new one every 10 minutes.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/server
touch build/.gdignore
godot4 --headless --path . --export-release "Linux Server" build/server/8ber-server.x86_64 2>&1 | grep -E "ERROR|SCRIPT" | grep -v X509 || true
rev=$(git rev-parse --short HEAD)
gh release create "server-$rev" build/server/8ber-server.x86_64 --title "Server $rev" \
  --notes "Headless co-op host for the Scareathon server (commit $rev)." --latest >/dev/null
echo "server program released: server-$rev"
