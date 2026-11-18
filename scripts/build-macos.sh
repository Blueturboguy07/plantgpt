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
# The updater files are made from the stapled app, never before: tauri build does not make
# them here (createUpdaterArtifacts off), because it would pack the app before notarization.
# After stapling, scripts/updater-pack-macos.sh packs and signs that app with the publik update
# key from the login keychain (service publik-update-key; never a file in the repo, never
# printed), and scripts/updater-latest-json.mjs writes latest.json with the absolute GitHub
# asset URL of the v<version> release. See docs/updates.md.
#
# Usage: scripts/build-macos.sh [--profile <notarytool keychain profile>] [--notes-file <file>]
# Out:   src-tauri/target/release/bundle/dmg/PlantGPT_<version>_<arch>.dmg
#        src-tauri/target/release/bundle/updater/PlantGPT_<version>_<arch>.app.tar.gz (+ .sig)
#        src-tauri/target/release/bundle/updater/latest.json
set -euo pipefail

cd "$(dirname "$0")/.."
PROFILE="publik"
NOTES_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --notes-file) NOTES_FILE="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
# The release repo whose v<version> assets latest.json points at.
REPO="${RELEASE_REPO:-Blueturboguy07/plantgpt}"
# The update key comes from the login keychain only (scripts/updater-pack-macos.sh reads it).
unset TAURI_SIGNING_PRIVATE_KEY TAURI_SIGNING_PRIVATE_KEY_PASSWORD
UPDATE_KEY_SERVICE="${UPDATE_KEY_SERVICE:-publik-update-key}"

IDENTITY="$(node -p "require('./src-tauri/tauri.conf.json').bundle.macOS.signingIdentity")"
VERSION="$(node -p "require('./src-tauri/tauri.conf.json').version")"
case "$(uname -m)" in
  arm64) ARCH="aarch64"; UPDATER_TARGET="darwin-aarch64" ;;
  x86_64) ARCH="x64"; UPDATER_TARGET="darwin-x86_64" ;;
  *) echo "unsupported arch $(uname -m)" >&2; exit 1 ;;
esac
[ -z "$NOTES_FILE" ] || [ -s "$NOTES_FILE" ] || { echo "no notes file at $NOTES_FILE" >&2; exit 1; }

if ! security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
  echo "Signing identity '$IDENTITY' is not in the keychain." >&2
  exit 1
fi

# A release build compiles in the publik app token (src-tauri/build.rs): PUBLIK_APP_TOKEN in the
# environment, or src-tauri/publik-app-token.txt filled by the release pipeline. Without it the
# app opens with "This build has no publik app token. Ask the developer for a new build."
if [ -z "${PUBLIK_APP_TOKEN:-}" ] && ! grep -q '^pat_' src-tauri/publik-app-token.txt 2>/dev/null; then
  echo "Refusing to build a release with no publik app token." >&2
  echo "Set PUBLIK_APP_TOKEN, or put the token of the listing 'plantgpt' in src-tauri/publik-app-token.txt." >&2
  exit 1
fi

# The update key must be there before the long build and two notarizations (values not read here).
for account in mann-private mann-password; do
  if ! security find-generic-password -s "$UPDATE_KEY_SERVICE" -a "$account" >/dev/null 2>&1; then
    echo "The login keychain has no '$UPDATE_KEY_SERVICE' item for '$account': no update bundle can be signed (docs/updates.md)." >&2
    exit 1
  fi
done

echo "==> Building signed PlantGPT.app ($IDENTITY)"
# No updater artifacts from tauri build: they are packed from the stapled app below.
npx tauri build --bundles app --config '{"bundle":{"createUpdaterArtifacts":false}}'

BUNDLE="src-tauri/target/release/bundle"
APP="$BUNDLE/macos/PlantGPT.app"
[ -d "$APP" ] || { echo "no app bundle at $APP" >&2; exit 1; }

echo "==> Notarizing the app"
ZIP="$BUNDLE/macos/PlantGPT.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"

echo "==> Update bundle and feed, from the stapled app"
# The updater installs exactly these bytes, so an update keeps the Developer ID signature, the
# notarization ticket and the TCC identity. latest.json is checked against the pubkey in
# tauri.conf.json and the signed version before it is written.
UPDATER_DIR="$BUNDLE/updater"
rm -rf "$UPDATER_DIR"
scripts/updater-pack-macos.sh "$APP" "$UPDATER_DIR"
TARBALL="$UPDATER_DIR/PlantGPT_${VERSION}_${ARCH}.app.tar.gz"
[ -s "$TARBALL" ] && [ -s "$TARBALL.sig" ] || { echo "no update bundle at $TARBALL" >&2; exit 1; }
if [ -n "$NOTES_FILE" ]; then NOTES=(--notes-file "$NOTES_FILE"); else NOTES=(--notes "PlantGPT $VERSION"); fi
node scripts/updater-latest-json.mjs --version "$VERSION" \
  --base-url "https://github.com/$REPO/releases/download/v$VERSION/" \
  --platform "$UPDATER_TARGET=$TARBALL" "${NOTES[@]}" --out "$UPDATER_DIR/latest.json"

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
echo "Release files (upload all four to the v$VERSION release with these names; docs/updates.md):"
ls -l "$DMG" "$TARBALL" "$TARBALL.sig" "$UPDATER_DIR/latest.json"
