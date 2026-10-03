#!/usr/bin/env bash
# Builds the web export and publishes it to the gh-pages branch (GitHub Pages),
# then publishes the matching Linux server program (tools/publish_server.sh) so
# the Scareathon server's co-op hosts stay on the same version as players.
set -euo pipefail
cd "$(dirname "$0")/.."
./tools/build_web.sh
rev=$(git rev-parse --short HEAD)
tmp=$(mktemp -d)
git worktree add --detach "$tmp" >/dev/null
(
  cd "$tmp"
  git checkout -q --orphan gh-pages-new
  git rm -rqf . >/dev/null 2>&1 || true
  cp -r "$OLDPWD"/build/web/. .
  touch .nojekyll
  git add -A
  git -c user.name=scabone98 -c user.email=scarbone.bsopr@gmail.com commit -qm "Web build of $rev"
  git push -qf origin HEAD:gh-pages
)
git worktree remove --force "$tmp"
git branch -D gh-pages-new >/dev/null 2>&1 || true
echo "published $rev"
./tools/publish_server.sh
