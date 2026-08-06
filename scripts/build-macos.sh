#!/usr/bin/env bash
#
# Builds, signs, notarizes and staples the PlantGPT dmg.
#
# Unlike publik's build-iris-macos.sh (which feeds Tauri APPLE_ID/APPLE_PASSWORD
# and lets it notarize), this uses a notarytool keychain profile so no password
# ever sits in the environment. The order matters: the .app is notarized and
# stapled BEFORE the dmg is created around it, then the dmg gets its own ticket
# — an unstapled layer has to be verified against Apple over the network, and
# that failure reads as a corrupt file to an offline user.
#
# Usage: scripts/build-macos.sh [--profile <notarytool keychain profile>]
set -euo pipefail

cd "$(dirname "$0")/.."
PROFILE="publik"
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

IDENTITY="$(node -p "require('./src-tauri/tauri.conf.json').bundle.macOS.signingIdentity")"
VERSION="$(node -p "require('./src-tauri/tauri.conf.json').version")"
case "$(uname -m)" in
  arm64) ARCH="aarch64" ;;
  x86_64) ARCH="x64" ;;
  *) echo "unsupported arch $(uname -m)" >&2; exit 1 ;;
esac

if ! security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
  echo "Signing identity '$IDENTITY' is not in the keychain." >&2
  exit 1
fi

echo "==> Building signed PlantGPT.app ($IDENTITY)"
npx tauri build --bundles app

BUNDLE="src-tauri/target/release/bundle"
APP="$BUNDLE/macos/PlantGPT.app"
[ -d "$APP" ] || { echo "no app bundle at $APP" >&2; exit 1; }

echo "==> Notarizing the app"
ZIP="$BUNDLE/macos/PlantGPT.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"

echo "==> Wrapping the stapled app in a dmg"
DMG_DIR="$BUNDLE/dmg"
DMG="$DMG_DIR/PlantGPT_${VERSION}_${ARCH}.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$DMG_DIR" "$STAGE/root"
cp -R "$APP" "$STAGE/root/PlantGPT.app"
ln -s /Applications "$STAGE/root/Applications"
rm -f "$DMG"
hdiutil create -volname "PlantGPT" -srcfolder "$STAGE/root" -ov -format UDZO "$DMG" -quiet
codesign --sign "$IDENTITY" "$DMG"

echo "==> Notarizing the disk image itself"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo "Done: $DMG"
