#!/usr/bin/env bash
# Configure Git to automatically use version-controlled hooks in .githooks

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

echo "Configuring core.hooksPath to .githooks..."
git config core.hooksPath .githooks
chmod +x .githooks/* scripts/*.py

echo "✅ Git hooks successfully installed and active!"
echo "Privacy guardrail will now prevent committing or pushing unauthorized email addresses."
