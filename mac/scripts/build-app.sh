#!/usr/bin/env bash
# Builds a signed, sandboxed Hearth.app into build/.
# Flags: --install (copy to ~/Applications), --run (open it).
# Env: SIGN_IDENTITY overrides the signing identity ("-" for ad hoc).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

INSTALL=0
RUN=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --run) RUN=1 ;;
    -h|--help) echo "Usage: $0 [--install] [--run]"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

if [[ ! -f Resources/AppIcon.icns ]]; then
  echo "==> Generating app icon"
  swift scripts/make-icon.swift
fi

echo "==> Building release binary"
if swift build -c release --arch arm64 --arch x86_64; then
  BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
  echo "    universal (arm64 + x86_64)"
else
  echo "    universal build failed, falling back to native arch"
  swift build -c release
  BIN_DIR="$(swift build -c release --show-bin-path)"
fi

APP="$ROOT/build/Hearth.app"
echo "==> Assembling $APP ($VERSION, build $BUILD_NUMBER)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Hearth" "$APP/Contents/MacOS/Hearth"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
CREDENTIALS=""
for f in Resources/HearthCredentials.plist "$HOME/.config/hearth/HearthCredentials.plist"; do
  if [[ -f "$f" ]]; then CREDENTIALS="$f"; break; fi
done
if [[ -n "$CREDENTIALS" ]]; then
  cp "$CREDENTIALS" "$APP/Contents/Resources/HearthCredentials.plist"
  echo "    bundled HearthCredentials.plist from $CREDENTIALS"
else
  echo "    no HearthCredentials.plist, the app will open to the own-project form"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Pick a stable identity. Ad hoc signatures change every build, which makes
# Keychain ask for access again after each update.
pick_identity() {
  local ids
  ids="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  for kind in "Developer ID Application" "Apple Development"; do
    local hit
    hit="$(grep "\"$kind" <<<"$ids" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)"
    if [[ -n "$hit" ]]; then echo "$hit"; return; fi
  done
  echo "-"
}
IDENTITY="${SIGN_IDENTITY:-$(pick_identity)}"

SIGN_ARGS=(--force --options runtime --entitlements Resources/Hearth.entitlements -s "$IDENTITY")
if [[ "$IDENTITY" == Developer\ ID* ]]; then
  SIGN_ARGS+=(--timestamp)
fi
echo "==> Signing with: $IDENTITY"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E '^(Identifier|Format|Authority|TeamIdentifier|Runtime)' | sed 's/^/    /' || true
echo "$IDENTITY" > "$ROOT/build/.sign-identity"

TARGET="$APP"
if [[ $INSTALL -eq 1 ]]; then
  mkdir -p "$HOME/Applications"
  # Quit a running copy so the new build replaces it cleanly.
  osascript -e 'quit app "Hearth"' 2>/dev/null || true
  sleep 1
  pkill -x Hearth 2>/dev/null || true
  rm -rf "$HOME/Applications/Hearth.app"
  cp -R "$APP" "$HOME/Applications/Hearth.app"
  TARGET="$HOME/Applications/Hearth.app"
  echo "==> Installed to $TARGET"
fi

if [[ $RUN -eq 1 ]]; then
  pkill -x Hearth 2>/dev/null || true
  open "$TARGET"
fi

echo "$TARGET"
