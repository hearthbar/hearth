#!/usr/bin/env bash
# Builds Hearth.app and packages it as a signed DMG in build/.
# Notarizes and staples when signed with Developer ID and a notarytool profile exists.
# Env: SIGN_IDENTITY, NOTARY_PROFILE (default "hearth").
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
VERSION="$(tr -d '[:space:]' < VERSION)"
PROFILE="${NOTARY_PROFILE:-hearth}"

./scripts/build-app.sh
IDENTITY="$(cat build/.sign-identity)"
TEAM_ID="$(codesign -dv build/Hearth.app 2>&1 | sed -n 's/^TeamIdentifier=//p')"
TEAM_ID="${TEAM_ID:-<team-id>}"

DMG="$ROOT/build/Hearth-$VERSION.dmg"
STAGE="$ROOT/build/dmg-stage"
RW="$ROOT/build/Hearth-rw.dmg"

echo "==> Creating $DMG"
rm -rf "$STAGE" "$DMG" "$RW"
mkdir -p "$STAGE"
cp -R build/Hearth.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -quiet -volname "Hearth" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW"

# Lay out the Finder window: big icons, app on the left, Applications on the right.
MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}')"
# Time-boxed: the first run may wait on an Automation permission prompt.
perl -e 'alarm 30; exec @ARGV' osascript <<EOF >/dev/null 2>&1 || echo "    (skipped window styling, Finder scripting not allowed)"
tell application "Finder"
  tell disk "Hearth"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 200, 740, 560}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set position of item "Hearth.app" of container window to {140, 170}
    set position of item "Applications" of container window to {400, 170}
    update without registering applications
    close
  end tell
end tell
EOF
sync
hdiutil detach -quiet "$MOUNT" || hdiutil detach -force -quiet "$MOUNT"

hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -rf "$RW" "$STAGE"

if [[ "$IDENTITY" != "-" ]]; then
  echo "==> Signing DMG"
  if [[ "$IDENTITY" == Developer\ ID* ]]; then
    codesign --force --timestamp -s "$IDENTITY" "$DMG"
  else
    codesign --force -s "$IDENTITY" "$DMG"
  fi
fi

if [[ "$IDENTITY" == Developer\ ID* ]]; then
  if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "==> Notarizing (profile: $PROFILE)"
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl -a -t open --context context:primary-signature -v "$DMG" || true
  else
    cat <<EOF

Note: signed with Developer ID, but no notarytool profile named "$PROFILE".
Set one up once, then run this again:
  xcrun notarytool store-credentials $PROFILE --apple-id <email> --team-id $TEAM_ID
EOF
  fi
else
  cat <<EOF

Note: signed with "$IDENTITY", not Developer ID.
This DMG works on this Mac. Other Macs will block it until it is signed
with Developer ID and notarized. One-time setup:
  1. Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application
     (needs a paid Apple Developer Program membership)
  2. xcrun notarytool store-credentials $PROFILE --apple-id <email> --team-id $TEAM_ID
Then run ./scripts/release.sh again.
EOF
fi

echo
echo "$DMG"
