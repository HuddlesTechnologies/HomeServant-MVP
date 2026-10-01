#!/bin/bash
# Claude Code on the web: installs what's needed to check both halves of
# the app before pushing — Flutter (same version as CI) for `flutter
# analyze` / `flutter test`, and the backend's npm packages for `tsc` and
# jest. Safe to run again: anything already installed is skipped.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

FLUTTER_VERSION=3.29.3 # keep in step with .github/workflows/ci.yml
FLUTTER_HOME="$HOME/flutter"

if [ ! -x "$FLUTTER_HOME/bin/flutter" ] || ! "$FLUTTER_HOME/bin/flutter" --version 2>/dev/null | grep -q "Flutter $FLUTTER_VERSION "; then
  rm -rf "$FLUTTER_HOME"
  curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ -C "$HOME"
fi
# The tarball's checkout is owned by another user; git refuses it otherwise.
git config --global --add safe.directory "$FLUTTER_HOME" 2>/dev/null || true

export PATH="$FLUTTER_HOME/bin:$PATH"
echo "export PATH=\"$FLUTTER_HOME/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"

flutter config --no-analytics >/dev/null 2>&1 || true
cd "$CLAUDE_PROJECT_DIR"
flutter pub get

cd "$CLAUDE_PROJECT_DIR/backend"
npm install --no-audit --no-fund
npx prisma generate
