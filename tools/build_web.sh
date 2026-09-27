#!/usr/bin/env bash
# Exports the web build to build/web.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/web
touch build/.gdignore  # keep Godot from importing its own export
godot4 --headless --path . --export-release "Web" build/web/index.html 2>&1 | grep -E "ERROR|SCRIPT" | grep -v X509 || true
echo "built: $(du -sh build/web | cut -f1)"
