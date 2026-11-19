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
# --app <PlantGPT.app>: no local build. Use this app instead (scripts/publik-release.sh passes the
# CI build of publik-build.yml, which is signed ad hoc): it is signed here with the Developer ID
# (nested code first, then the app with the hardened runtime, the repo's entitlements and a secure
# timestamp), and then everything below runs on it as after a local build.
#
# Usage: scripts/build-macos.sh [--profile <notarytool keychain profile>] [--notes-file <file>] [--app <PlantGPT.app>]
# Out:   src-tauri/target/release/bundle/dmg/PlantGPT_<version>_<arch>.dmg
#        src-tauri/target/release/bundle/updater/PlantGPT_<version>_<arch>.app.tar.gz (+ .sig)
#        src-tauri/target/release/bundle/updater/latest.json
set -euo pipefail

cd "$(dirname "$0")/.."
PROFILE="publik"
NOTES_FILE=""
FROM_APP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --notes-file) NOTES_FILE="$2"; shift 2 ;;
    --app) FROM_APP="$2"; shift 2 ;;
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
if [ -n "$FROM_APP" ]; then
  [ -d "$FROM_APP/Contents/MacOS" ] || { echo "--app $FROM_APP is not an app bundle" >&2; exit 1; }
  FROM_APP="$(cd "$(dirname "$FROM_APP")" && pwd)/$(basename "$FROM_APP")"
  FROM_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$FROM_APP/Contents/Info.plist")"
  [ "$FROM_VERSION" = "$VERSION" ] || { echo "--app is version $FROM_VERSION, tauri.conf.json says $VERSION" >&2; exit 1; }
fi

if ! security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
  echo "Signing identity '$IDENTITY' is not in the keychain." >&2
  exit 1
fi

# A release build compiles in the publik app token (src-tauri/build.rs): PUBLIK_APP_TOKEN in the
# environment, or src-tauri/publik-app-token.txt filled by the release pipeline. Without it the
# app opens with "This build has no publik app token. Ask the developer for a new build."
# With --app the token is already compiled in: the binary must carry one.
if [ -n "$FROM_APP" ]; then
  FROM_EXE="$FROM_APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$FROM_APP/Contents/Info.plist")"
  if ! LC_ALL=C grep -a -o -E 'pat_[A-Za-z0-9_-]{30,}' "$FROM_EXE" >/dev/null; then
    echo "Refusing to sign an app with no publik app token compiled in: $FROM_APP" >&2
    exit 1
  fi
elif [ -z "${PUBLIK_APP_TOKEN:-}" ] && ! grep -q '^pat_' src-tauri/publik-app-token.txt 2>/dev/null; then
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

BUNDLE="src-tauri/target/release/bundle"
APP="$BUNDLE/macos/PlantGPT.app"
if [ -z "$FROM_APP" ]; then
  echo "==> Building signed PlantGPT.app ($IDENTITY)"
  # No updater artifacts from tauri build: they are packed from the stapled app below.
  npx tauri build --bundles app --config '{"bundle":{"createUpdaterArtifacts":false}}'
else
  echo "==> Signing $FROM_APP with $IDENTITY (no local build)"
  rm -rf "$APP"
  mkdir -p "$BUNDLE/macos"
  ditto "$FROM_APP" "$APP"
  # No extended attributes in a bundle that is signed (codesign refuses "detritus").
  xattr -cr "$APP"
  MAIN_EXE="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
  SIGN=(codesign --force --options runtime --timestamp --sign "$IDENTITY")
  # Inner code first: every Mach-O file except the main executable, then nested bundles
  # (deepest first), then the app itself with the entitlements, as tauri build signs it.
  while IFS= read -r -d '' f; do
    [ "$f" = "$MAIN_EXE" ] && continue
    if file -b "$f" | grep -q 'Mach-O'; then echo "    inner: ${f#"$APP"/}"; "${SIGN[@]}" "$f"; fi
  done < <(find "$APP/Contents" -type f -print0)
  while IFS= read -r -d '' d; do
    echo "    nested bundle: ${d#"$APP"/}"; "${SIGN[@]}" "$d"
  done < <(find "$APP/Contents" -depth -mindepth 1 -type d \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' -o -name '*.appex' -o -name '*.bundle' \) -print0)
  "${SIGN[@]}" --entitlements src-tauri/entitlements.plist "$APP"
  codesign --verify --strict --deep "$APP"
  codesign -dvv "$APP" 2>&1 | grep -E '^(Identifier|Authority=Developer ID Application|TeamIdentifier|Timestamp)=|flags=' || true
fi
[ -d "$APP" ] || { echo "no app bundle at $APP" >&2; exit 1; }

# notarytool --wait returns when Apple has answered. Only "Accepted" passes; on any other answer
# the submission log (it holds no secret) is printed and the script stops.
notarize() {
  local out id
  out="$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait 2>&1)" || true
  printf '%s\n' "$out"
  id="$(printf '%s\n' "$out" | awk '$1 == "id:" {print $2; exit}')"
  if ! printf '%s\n' "$out" | grep -q '^ *status: Accepted'; then
    [ -z "$id" ] || xcrun notarytool log "$id" --keychain-profile "$PROFILE" || true
    echo "Apple did not accept $1 for notarization." >&2
    exit 1
  fi
}

echo "==> Notarizing the app"
ZIP="$BUNDLE/macos/PlantGPT.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP"
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
codesign --sign "$IDENTITY" --timestamp "$DMG"

echo "==> Notarizing the disk image itself"
notarize "$DMG"
xcrun stapler staple "$DMG"

echo "Done: $DMG"
echo "Release files (upload all four to the v$VERSION release with these names; docs/updates.md):"
ls -l "$DMG" "$TARBALL" "$TARBALL.sig" "$UPDATER_DIR/latest.json"
