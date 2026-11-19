#!/usr/bin/env bash
#
# The one release command for PlantGPT (macOS, Apple silicon). docs/updates.md, "Cut a release".
#
#   scripts/publik-release.sh <version> [--notes-file <file>] [--draft-only] [--keep]
#
#   1. Checks: the release branch, a clean tree equal to origin/<branch>, <version> in every file a
#      version bump touches, <version> higher than the last release, the tag v<version> free (or a
#      draft release of this commit, which is resumed), the Developer ID identity, the notarytool
#      profile, the update key items (their values are not read here), gh, node, the Tauri CLI and
#      free disk.
#   2. CI build: publik-build.yml on this commit (a successful run of the same commit is reused),
#      waits for it, downloads the app (signed ad hoc, the publik app token compiled in) and checks it.
#   3. scripts/build-macos.sh --app <the CI app>: Developer ID signing on this Mac (inner code first,
#      hardened runtime, the repo's entitlements), notarization, staple, the signed update bundle,
#      latest.json, and the dmg (notarized and stapled too). No local cargo build.
#   4. A DRAFT release v<version> on this commit with the five assets of the last release:
#      plantgpt-<v>-macos-arm64.dmg, PlantGPT_<v>_aarch64.app.tar.gz (+ .sig), latest.json,
#      SHA256SUMS.txt. An asset that is already on the draft with the same SHA-256 is not sent again.
#   5. Downloads every asset of the draft into an empty folder and verifies it: the feed signature
#      with the app's public key (and with the key of the last release, which installed copies
#      have), hashes, the version in Info.plist = feed = tag, codesign, hardened runtime, team,
#      stapled tickets, Gatekeeper ("Notarized Developer ID") for the app and the dmg, the
#      designated requirement, entitlements and app token the same as in the last release.
#   6. Publishes the draft only when every check passed, then checks the public asset URLs.
#
# Run the same command again after any failure: work that is done and still valid (the CI run, the
# signed and notarized files, the draft and its assets) is kept and checked again; the rest runs.
# The script starts no app and prints no secret: scripts/updater-pack-macos.sh reads the update key
# from the login keychain and gives it to `tauri signer sign` only.
#
# --draft-only  stop after step 5 (the draft is verified, not published).
# --keep        keep the work folder and the build output after publishing.
# --verify <dir> only run the checks of step 5 on the five assets of v<version> in <dir> (for
#               example an older release, downloaded with gh release download), against the
#               release before it (PUBLIK_RELEASE_PREV_TAG overrides which one), and stop.
# Env: RELEASE_REPO (default Blueturboguy07/plantgpt), RELEASE_BRANCH (default main),
#      NOTARY_PROFILE (default publik), TAURI_CLI, PUBLIK_RELEASE_WORK,
#      PUBLIK_RELEASE_MIN_FREE_MB (default 1500), PUBLIK_RELEASE_POLL (seconds between two status
#      calls while CI builds; default 90).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="PlantGPT"
BUNDLE_ID="com.mannbellani.plantgpt"
TEAM="R5R3ZS54LV"
REPO="${RELEASE_REPO:-Blueturboguy07/plantgpt}"
BRANCH="${RELEASE_BRANCH:-main}"
PROFILE="${NOTARY_PROFILE:-publik}"
UPDATE_KEY_SERVICE="${UPDATE_KEY_SERVICE:-publik-update-key}"
WORKFLOW="publik-build.yml"
ARTIFACT="PlantGPT-macos-arm64-app"
CI_ZIP="PlantGPT-macos-arm64.app.zip"
FEED_URL="https://publikhq.com/api/updates/plantgpt/latest.json"

V=""; NOTES_FILE=""; DRAFT_ONLY=0; KEEP=0; VERIFY_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --notes-file) NOTES_FILE="$2"; shift 2 ;;
    --verify) VERIFY_DIR="$(cd "$2" && pwd)"; shift 2 ;;
    --draft-only) DRAFT_ONLY=1; shift ;;
    --keep) KEEP=1; shift ;;
    -h|--help) sed -n '2,44p' "$0"; exit 0 ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) [ -z "$V" ] || { echo "one version only" >&2; exit 2; }; V="${1#v}"; shift ;;
  esac
done
[ -n "$V" ] || { echo "usage: scripts/publik-release.sh <version> [--notes-file <file>] [--draft-only] [--keep]" >&2; exit 2; }
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "the version must be x.y.z: $V" >&2; exit 2; }
if [ -n "$NOTES_FILE" ]; then
  [ -s "$NOTES_FILE" ] || { echo "no notes file at $NOTES_FILE" >&2; exit 2; }
  NOTES_FILE="$(cd "$(dirname "$NOTES_FILE")" && pwd)/$(basename "$NOTES_FILE")"
fi

TAG="v$V"
DMG_ASSET="plantgpt-$V-macos-arm64.dmg"
TAR_ASSET="PlantGPT_${V}_aarch64.app.tar.gz"
SIG_ASSET="$TAR_ASSET.sig"
ASSETS=("$DMG_ASSET" "$TAR_ASSET" "$SIG_ASSET" "latest.json" "SHA256SUMS.txt")
BASE_URL="https://github.com/$REPO/releases/download/$TAG/"
BUNDLE="src-tauri/target/release/bundle"
OUT_APP="$BUNDLE/macos/PlantGPT.app"
OUT_DMG="$BUNDLE/dmg/PlantGPT_${V}_aarch64.dmg"
OUT_TAR="$BUNDLE/updater/$TAR_ASSET"
OUT_FEED="$BUNDLE/updater/latest.json"
WORK="${PUBLIK_RELEASE_WORK:-$ROOT/src-tauri/target/publik-release/$TAG}"
STAGE="$WORK/assets"

step() { printf '\n==> %s\n' "$*"; }
die() { printf '\nSTOP: %s\n' "$*" >&2; [ -z "${TAG_STATE:-}" ] || printf 'Nothing was published. %s\n' "$TAG_STATE" >&2; exit 1; }
FAILS=0; PASSES=0
pass() { PASSES=$((PASSES + 1)); printf '  PASS  %s%s\n' "$1" "${2:+  ($2)}"; }
fail() { FAILS=$((FAILS + 1)); printf '  FAIL  %s%s\n' "$1" "${2:+  ($2)}"; }
check() { local name="$1" detail="$2"; shift 2; if "$@" >/dev/null 2>&1; then pass "$name" "$detail"; else fail "$name" "$detail"; fi; }
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null; }
exe_of() { echo "$1/Contents/MacOS/$(plist "$1" CFBundleExecutable)"; }
dr_of() { codesign -d -r- "$1" 2>&1 | sed -n 's/^designated => //p'; }
cdhash_of() { codesign -dvvv "$1" 2>&1 | sed -n 's/^CDHash=//p'; }
ent_of() { codesign -d --entitlements :- "$1" 2>/dev/null | plutil -convert json -o - - 2>/dev/null || echo "{}"; }
# The publik app token is public by design, but only a short hash of it is ever printed.
token_of() { LC_ALL=C grep -a -o -E 'pat_[A-Za-z0-9_-]{30,}' "$(exe_of "$1")" | sort -u | shasum -a 256 | cut -c1-12; }
sha_of() { shasum -a 256 "$1" | cut -d' ' -f1; }
json() { node -e 'const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); const v=(new Function("j","return ("+process.argv[2]+")"))(j); console.log(typeof v==="string"?v:JSON.stringify(v))' "$1" "$2"; }
free_mb() { echo $(( $(df -k "$ROOT" | awk 'NR==2 {print $4}') / 1024 )); }
mkdir -p "$WORK"

# The last release, for the checks "the same as in the last release": its app (from the update
# bundle, else the dmg), its tauri.conf.json, designated requirement, entitlements and app token.
load_prev() {
  PREV="$WORK/prev"
  if [ ! -d "$PREV/app/PlantGPT.app" ] || [ "$(cat "$PREV/tag" 2>/dev/null)" != "$PREV_TAG" ]; then
    rm -rf "$PREV"; mkdir -p "$PREV/dl" "$PREV/app"
    if gh release download "$PREV_TAG" -R "$REPO" -p '*.app.tar.gz' -D "$PREV/dl" 2>/dev/null; then
      tar -xzf "$PREV"/dl/*.app.tar.gz -C "$PREV/app"
    else
      gh release download "$PREV_TAG" -R "$REPO" -p '*.dmg' -D "$PREV/dl"
      local mnt; mnt="$(mktemp -d)"; hdiutil attach "$PREV"/dl/*.dmg -nobrowse -readonly -mountpoint "$mnt" -quiet
      ditto "$mnt/PlantGPT.app" "$PREV/app/PlantGPT.app"; hdiutil detach "$mnt" -quiet
    fi
    rm -rf "$PREV/dl"; echo "$PREV_TAG" > "$PREV/tag"
  fi
  git show "$PREV_TAG:src-tauri/tauri.conf.json" > "$PREV/tauri.conf.json"
  PREV_APP="$PREV/app/PlantGPT.app"
  PREV_DR="$(dr_of "$PREV_APP")"; PREV_ENT="$(ent_of "$PREV_APP")"; PREV_TOKEN="$(token_of "$PREV_APP" || true)"
  PREV_HAS_KEY="$(node -p "Boolean(require('$PREV/tauri.conf.json').plugins?.updater?.pubkey)")"
  [ -n "$PREV_DR" ] || die "could not read the designated requirement of $PREV_TAG"
  echo "  ok    $PREV_TAG: designated requirement read, app token #$PREV_TOKEN, update key in its config: $PREV_HAS_KEY"
}

# Checks of a built app against the last release (the CI app, then the signed one).
app_checks() {
  local app="$1" what="$2" exe
  exe="$(exe_of "$app")"
  check "$what: version $V in Info.plist" "$(plist "$app" CFBundleShortVersionString)/$(plist "$app" CFBundleVersion)" \
    test "$(plist "$app" CFBundleShortVersionString)/$(plist "$app" CFBundleVersion)" = "$V/$V"
  check "$what: bundle id $BUNDLE_ID" "" test "$(plist "$app" CFBundleIdentifier)" = "$BUNDLE_ID"
  check "$what: arm64 binary" "$(lipo -archs "$exe")" test "$(lipo -archs "$exe")" = arm64
  check "$what: the app token of $PREV_TAG is compiled in" "#$(token_of "$app")" test "$(token_of "$app")" = "$PREV_TOKEN"
  check "$what: the update feed is $FEED_URL" "" env LC_ALL=C grep -a -q -F "$FEED_URL" "$exe"
  check "$what: no test feed compiled in (PUBLIK_UPDATE_ENDPOINT)" "" sh -c "! LC_ALL=C grep -a -q -E 'https?://127\\.0\\.0\\.1:[0-9]+/latest\\.json' '$exe'"
}

# Every check of the release files in one folder (the staged files, then the download).
verify_assets() {
  local d="$1" label="$2" t="$WORK/verify-$2" app mnt
  FAILS=0
  rm -rf "$t"; mkdir -p "$t/tar" "$t/q"
  echo "  -- $label ($d)"
  check "exactly the five release assets" "$(cd "$d" && ls | tr '\n' ' ')" \
    test "$(cd "$d" && ls | sort | tr '\n' ' ')" = "$(printf '%s\n' "${ASSETS[@]}" | sort | tr '\n' ' ')"
  check "SHA256SUMS.txt matches the dmg and the update bundle" "" sh -c "cd '$d' && shasum -a 256 -c SHA256SUMS.txt"
  local fv fk fu fs
  fv="$(json "$d/latest.json" 'j.version')"; fk="$(json "$d/latest.json" 'Object.keys(j.platforms).join(",")')"
  fu="$(json "$d/latest.json" 'j.platforms["darwin-aarch64"].url')"; fs="$(json "$d/latest.json" 'j.platforms["darwin-aarch64"].signature')"
  check "latest.json: version $V" "$fv" test "$fv" = "$V"
  check "latest.json: platform darwin-aarch64 only" "$fk" test "$fk" = "darwin-aarch64"
  check "latest.json: absolute GitHub asset URL" "$fu" test "$fu" = "$BASE_URL$TAR_ASSET"
  check "latest.json: signature = $SIG_ASSET" "" test "$fs" = "$(tr -d '\n' < "$d/$SIG_ASSET")"
  check "feed signature verifies with the app's public key and names $V" "tauri.conf.json at $(git rev-parse --short HEAD)" \
    node scripts/updater-latest-json.mjs --version "$V" --base-url "$BASE_URL" --platform "darwin-aarch64=$d/$TAR_ASSET" --notes x --out "$t/regen.json"
  if [ "$PREV_HAS_KEY" = true ]; then
    check "feed signature verifies with the public key of $PREV_TAG (what installed copies check)" "" \
      node scripts/updater-latest-json.mjs --config "$PREV/tauri.conf.json" --version "$V" --base-url "$BASE_URL" --platform "darwin-aarch64=$d/$TAR_ASSET" --notes x --out "$t/regen-prev.json"
  else
    echo "  ----  $PREV_TAG has no updater, so no installed copy checks this signature"
  fi
  check "the update bundle has no AppleDouble files" "" sh -c "! tar -tzf '$d/$TAR_ASSET' | grep -q '/\\._'"
  tar -xzf "$d/$TAR_ASSET" -C "$t/tar"
  app="$t/tar/PlantGPT.app"
  check "the update bundle holds PlantGPT.app only" "$(ls "$t/tar" | tr '\n' ' ')" test "$(ls "$t/tar")" = "PlantGPT.app"
  app_checks "$app" "update bundle"
  check "codesign: the seal is intact (deep, strict)" "" codesign --verify --deep --strict "$app"
  local info; info="$(codesign -dvvv "$app" 2>&1)"
  check "codesign: Developer ID Application, team $TEAM" "" sh -c "printf '%s\n' \"\$1\" | grep -q -x 'Authority=$IDENTITY' && printf '%s\n' \"\$1\" | grep -q -x 'TeamIdentifier=$TEAM'" _ "$info"
  check "codesign: hardened runtime and a secure timestamp" "" sh -c "printf '%s\n' \"\$1\" | grep -q 'flags=.*runtime' && printf '%s\n' \"\$1\" | grep -q '^Timestamp='" _ "$info"
  check "designated requirement = $PREV_TAG (TCC grants carry over)" "" test "$(dr_of "$app")" = "$PREV_DR"
  check "entitlements = $PREV_TAG" "$(ent_of "$app" | head -c 60)" test "$(ent_of "$app")" = "$PREV_ENT"
  check "notarization ticket stapled to the app" "" xcrun stapler validate "$app"
  ditto "$app" "$t/q/PlantGPT.app"; xattr -w com.apple.quarantine "0083;$(printf %x "$(date +%s)");Safari;" "$t/q/PlantGPT.app"
  local gk; gk="$(spctl -a -t exec -vv "$t/q/PlantGPT.app" 2>&1)"
  check "Gatekeeper accepts the quarantined app: Notarized Developer ID" "$(printf '%s' "$gk" | tr '\n' ' ' | sed "s#$t/q/##")" \
    sh -c "printf '%s\n' \"\$1\" | grep -q ': accepted' && printf '%s\n' \"\$1\" | grep -q -x 'source=Notarized Developer ID'" _ "$gk"
  check "notarization ticket stapled to the dmg" "" xcrun stapler validate "$d/$DMG_ASSET"
  check "the dmg signature is intact" "" codesign --verify "$d/$DMG_ASSET"
  cp "$d/$DMG_ASSET" "$t/q/$DMG_ASSET"; xattr -w com.apple.quarantine "0083;$(printf %x "$(date +%s)");Safari;" "$t/q/$DMG_ASSET"
  gk="$(spctl -a -t open --context context:primary-signature -vv "$t/q/$DMG_ASSET" 2>&1)"
  check "Gatekeeper accepts the quarantined dmg: Notarized Developer ID" "$(printf '%s' "$gk" | tr '\n' ' ' | sed "s#$t/q/##")" \
    sh -c "printf '%s\n' \"\$1\" | grep -q ': accepted' && printf '%s\n' \"\$1\" | grep -q -x 'source=Notarized Developer ID'" _ "$gk"
  rm -f "$t/q/$DMG_ASSET"
  mnt="$(mktemp -d)"
  if hdiutil attach "$d/$DMG_ASSET" -nobrowse -readonly -mountpoint "$mnt" -quiet; then
    check "the dmg holds the same app as the update bundle (cdhash)" "$(cdhash_of "$mnt/PlantGPT.app")" test "$(cdhash_of "$mnt/PlantGPT.app")" = "$(cdhash_of "$app")"
    check "the dmg has the Applications link" "" test -L "$mnt/Applications"
    hdiutil detach "$mnt" -quiet || true
  else
    fail "the dmg mounts"
  fi
  echo "  -- scripts/verify-macos.sh --require-notarized --no-launch"
  if scripts/verify-macos.sh --require-notarized --no-launch --app "$app" --dmg "$d/$DMG_ASSET" > "$t/verify-macos.log" 2>&1; then
    pass "scripts/verify-macos.sh --require-notarized --no-launch"
  else
    fail "scripts/verify-macos.sh --require-notarized --no-launch" "$(grep -c FAIL "$t/verify-macos.log") failure(s)"
    sed 's/^/        /' "$t/verify-macos.log"
  fi
  rm -rf "$t"
  echo "  $label: $PASSES passed so far, $FAILS failed"
  [ "$FAILS" = 0 ]
}

if [ -n "$VERIFY_DIR" ]; then
  step "Verify the release files of $TAG in $VERIFY_DIR"
  IDENTITY="$(node -p "require('./src-tauri/tauri.conf.json').bundle.macOS.signingIdentity")"
  PREV_TAG="${PUBLIK_RELEASE_PREV_TAG:-$(gh release list -R "$REPO" --exclude-drafts --limit 100 --json tagName -q '.[].tagName' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | awk -v t="$TAG" '$0 == t {exit} {p = $0} END {print p}')}"
  [ -n "$PREV_TAG" ] || die "no release before $TAG"
  load_prev
  RC=0; verify_assets "$VERIFY_DIR" verify || RC=1
  [ "$KEEP" = 1 ] || rm -rf "$WORK"
  if [ "$RC" = 0 ]; then echo "All $PASSES checks passed."; else echo "$FAILS check(s) failed."; fi
  exit "$RC"
fi

# ---------------------------------------------------------------------------------------------
step "1/6 Checks ($APP_NAME $V, $REPO, branch $BRANCH)"
for tool in gh node git codesign xcrun hdiutil spctl security shasum ditto; do
  command -v "$tool" >/dev/null || die "$tool is not installed"
done
gh auth status -h github.com >/dev/null 2>&1 || die "gh is not logged in (gh auth login)"
[ "$(git rev-parse --abbrev-ref HEAD)" = "$BRANCH" ] || die "check out $BRANCH (the release branch) first"
git fetch -q origin "$BRANCH" --tags
[ -z "$(git status --porcelain)" ] || die "the working tree is not clean (git status): commit or stash first"
SHA="$(git rev-parse HEAD)"
[ "$SHA" = "$(git rev-parse "origin/$BRANCH")" ] || die "HEAD is not origin/$BRANCH: push or pull first (CI builds the pushed commit)"
echo "  commit $SHA"

BAD=0
while IFS=$'\t' read -r have file; do
  if [ "$have" = "$V" ]; then echo "  ok    $file = $have"; else echo "  FAIL  $file = $have (want $V)"; BAD=1; fi
done < <(node -e '
const fs = require("fs");
const lock = JSON.parse(fs.readFileSync("package-lock.json", "utf8"));
const cargo = fs.readFileSync("src-tauri/Cargo.toml", "utf8").match(/^\[package\][^[]*?^version\s*=\s*"([^"]+)"/m);
const cargoLock = fs.readFileSync("src-tauri/Cargo.lock", "utf8").match(/\[\[package\]\]\nname = "plantgpt"\nversion = "([^"]+)"/);
const rows = [
  ["src-tauri/tauri.conf.json", JSON.parse(fs.readFileSync("src-tauri/tauri.conf.json", "utf8")).version],
  ["src-tauri/Cargo.toml", cargo && cargo[1]],
  ["src-tauri/Cargo.lock (plantgpt)", cargoLock && cargoLock[1]],
  ["package.json", JSON.parse(fs.readFileSync("package.json", "utf8")).version],
  ["package-lock.json", lock.version],
  ["package-lock.json (packages[\"\"])", lock.packages && lock.packages[""] && lock.packages[""].version],
];
for (const [file, v] of rows) console.log(`${v || "(none)"}\t${file}`);
')
[ "$BAD" = 0 ] || die "bump the version in every file above, commit and push (docs/updates.md, Cut a release)"

PREV_TAG="$(gh release list -R "$REPO" --exclude-drafts --limit 100 --json tagName -q '.[].tagName' \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | grep -v -x -F "$TAG" | sort -V | tail -1 || true)"
[ -n "$PREV_TAG" ] || die "no earlier release to compare with"
[ "$(printf '%s\n%s\n' "${PREV_TAG#v}" "$V" | sort -V | tail -1)" = "$V" ] || die "$V is not higher than the last release $PREV_TAG"
echo "  ok    $V is higher than the last release $PREV_TAG"

# The releases API lists drafts too (gh release view may not find a draft by its tag).
REL_ROWS="$(gh api "repos/$REPO/releases?per_page=100" --paginate -q ".[] | select(.tag_name == \"$TAG\") | \"\(.id) \(.draft) \(.target_commitish)\"")"
TAG_REMOTE="$(git ls-remote --tags origin "refs/tags/$TAG" | cut -f1)"
RESUME=0
if [ -n "$REL_ROWS" ]; then
  [ "$(printf '%s\n' "$REL_ROWS" | wc -l | tr -d ' ')" = 1 ] || die "more than one release has the tag $TAG: delete the extra drafts first"
  read -r REL_ID REL_DRAFT TARGET <<< "$REL_ROWS"
  [ "$REL_DRAFT" = true ] || die "$TAG is already published"
  [ "$TARGET" = "$SHA" ] || die "a draft $TAG exists for $TARGET, not $SHA: delete that draft or release from that commit"
  RESUME=1
  echo "  ok    a draft $TAG of this commit exists (release $REL_ID): resuming it"
fi
if [ -n "$TAG_REMOTE" ] && [ "$TAG_REMOTE" != "$SHA" ]; then die "the tag $TAG already exists on origin at $TAG_REMOTE"; fi
[ "$RESUME" = 1 ] || [ -z "$TAG_REMOTE" ] || die "the tag $TAG already exists with no release: pick another version"
[ "$RESUME" = 1 ] || echo "  ok    the tag $TAG is free"

IDENTITY="$(node -p "require('./src-tauri/tauri.conf.json').bundle.macOS.signingIdentity")"
case "$IDENTITY" in *"($TEAM)") ;; *) die "tauri.conf.json names the signing identity '$IDENTITY', not one of team $TEAM" ;; esac
security find-identity -v -p codesigning | grep -qF "\"$IDENTITY\"" || die "the keychain has no valid '$IDENTITY'"
echo "  ok    signing identity: $IDENTITY"
for account in mann-private mann-password; do
  security find-generic-password -s "$UPDATE_KEY_SERVICE" -a "$account" >/dev/null 2>&1 \
    || die "the login keychain has no '$UPDATE_KEY_SERVICE' item for '$account' (docs/updates.md, The key)"
done
echo "  ok    update key items: $UPDATE_KEY_SERVICE (mann-private, mann-password; not read here)"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 || die "the notarytool keychain profile '$PROFILE' does not work"
echo "  ok    notarytool profile: $PROFILE"

if [ -z "${TAURI_CLI:-}" ] && [ ! -x node_modules/.bin/tauri ]; then
  # No node_modules on the release Mac: the Tauri CLI of package.json through npx, for `tauri signer sign`.
  CLI_VERSION="$(node -p "require('./package.json').devDependencies['@tauri-apps/cli'].replace(/^[^0-9]*/, '')")"
  mkdir -p "$WORK/bin"
  printf '#!/bin/sh\nexec npx --yes "@tauri-apps/cli@%s" "$@"\n' "$CLI_VERSION" > "$WORK/bin/tauri"
  chmod +x "$WORK/bin/tauri"
  export TAURI_CLI="$WORK/bin/tauri"
fi
TAURI_VERSION="$("${TAURI_CLI:-node_modules/.bin/tauri}" --version 2>/dev/null)" || die "no working Tauri CLI (set TAURI_CLI)"
echo "  ok    Tauri CLI: $TAURI_VERSION"
FREE="$(free_mb)"
[ "$FREE" -ge "${PUBLIK_RELEASE_MIN_FREE_MB:-1500}" ] || die "only $FREE MB free on this disk; the release needs ${PUBLIK_RELEASE_MIN_FREE_MB:-1500} MB"
echo "  ok    free disk: $FREE MB"
load_prev
TAG_STATE="$( [ "$RESUME" = 1 ] && echo "The draft $TAG stays a draft." || echo "No release was made.")"

# ---------------------------------------------------------------------------------------------
BUILT_OK="$WORK/built.ok"
built_valid() {
  [ -s "$BUILT_OK" ] && grep -q -x "commit $SHA" "$BUILT_OK" \
    && (grep -v '^commit ' "$BUILT_OK" | shasum -a 256 -c - >/dev/null 2>&1) \
    && xcrun stapler validate "$OUT_DMG" >/dev/null 2>&1 && xcrun stapler validate "$OUT_APP" >/dev/null 2>&1
}
if built_valid; then
  step "2/6 CI build: skipped (signed and notarized files of $SHA are already in $BUNDLE)"
  step "3/6 Sign, notarize, staple, update bundle, feed, dmg: skipped (done; hashes match $BUILT_OK)"
else
  step "2/6 CI build ($WORKFLOW on $SHA)"
  runs() {
    gh run list -R "$REPO" -w "$WORKFLOW" -b "$BRANCH" -L 30 --json databaseId,headSha,status,conclusion,createdAt \
      -q "[.[] | select(.headSha == \"$SHA\")] | sort_by(.createdAt) | reverse | .[] | \"\(.databaseId) \(.status) \(.conclusion)\""
  }
  has_artifact() {
    [ -n "$(gh api "repos/$REPO/actions/runs/$1/artifacts" -q ".artifacts[] | select(.name == \"$ARTIFACT\" and .expired == false) | .id")" ]
  }
  RUN=""
  while read -r id status conclusion; do
    [ -n "$id" ] || continue
    if [ "$status" = completed ] && [ "$conclusion" = success ] && has_artifact "$id"; then RUN="$id"; echo "  reusing the successful run $id"; break; fi
    if [ "$status" != completed ]; then RUN="$id"; echo "  waiting for the running run $id"; break; fi
  done < <(runs)
  if [ -z "$RUN" ]; then
    T0="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    gh workflow run "$WORKFLOW" -R "$REPO" --ref "$BRANCH"
    for _ in $(seq 1 8); do
      sleep 15
      RUN="$(gh run list -R "$REPO" -w "$WORKFLOW" -b "$BRANCH" -e workflow_dispatch -L 10 --json databaseId,headSha,createdAt \
        -q "[.[] | select(.headSha == \"$SHA\" and .createdAt >= \"$T0\")] | sort_by(.createdAt) | last | .databaseId // empty")"
      [ -z "$RUN" ] || break
    done
    [ -n "$RUN" ] || die "the $WORKFLOW run did not start"
    echo "  started run $RUN"
  fi
  echo "  https://github.com/$REPO/actions/runs/$RUN"
  # One API call per poll, every PUBLIK_RELEASE_POLL seconds (default 90): the GitHub API limit is
  # shared by everything that uses this token. Up to 90 minutes.
  LAST=""; POLL="${PUBLIK_RELEASE_POLL:-90}"
  for _ in $(seq 1 $((5400 / POLL))); do
    STATE="$(gh run view "$RUN" -R "$REPO" --json status,conclusion -q '"\(.status) \(.conclusion)"')"
    [ "$STATE" = "$LAST" ] || { echo "  $(date -u +%H:%M:%S) $STATE"; LAST="$STATE"; }
    case "$STATE" in completed*) break ;; esac
    sleep "$POLL"
  done
  [ "$STATE" = "completed success" ] || die "the CI build ended '$STATE': https://github.com/$REPO/actions/runs/$RUN"
  rm -rf "$WORK/ci"; mkdir -p "$WORK/ci"
  gh run download "$RUN" -R "$REPO" -n "$ARTIFACT" -D "$WORK/ci"
  ditto -x -k "$WORK/ci/$CI_ZIP" "$WORK/ci/app"
  rm -f "$WORK/ci/$CI_ZIP"
  CI_APP="$WORK/ci/app/PlantGPT.app"
  [ -d "$CI_APP" ] || die "the CI artifact has no PlantGPT.app"
  FAILS=0; app_checks "$CI_APP" "CI app"
  [ "$FAILS" = 0 ] || die "the CI app failed $FAILS check(s)"

  step "3/6 Sign with the Developer ID, notarize, staple, update bundle, feed, dmg (scripts/build-macos.sh --app)"
  if [ -n "$NOTES_FILE" ]; then NOTES_ARG=(--notes-file "$NOTES_FILE"); else NOTES_ARG=(); fi
  RELEASE_REPO="$REPO" NOTARY_PROFILE="$PROFILE" scripts/build-macos.sh --profile "$PROFILE" --app "$CI_APP" ${NOTES_ARG[@]+"${NOTES_ARG[@]}"}
  for f in "$OUT_DMG" "$OUT_TAR" "$OUT_TAR.sig" "$OUT_FEED"; do [ -s "$f" ] || die "build-macos.sh made no $f"; done
  { echo "commit $SHA"; shasum -a 256 "$OUT_DMG" "$OUT_TAR" "$OUT_TAR.sig" "$OUT_FEED"; } > "$BUILT_OK"
  rm -rf "$WORK/ci"   # one copy: the signed app is in $OUT_APP
fi

# ---------------------------------------------------------------------------------------------
# ---------------------------------------------------------------------------------------------
step "4/6 Draft release $TAG on $SHA"
rm -rf "$STAGE"; mkdir -p "$STAGE"
ln "$OUT_DMG" "$STAGE/$DMG_ASSET" 2>/dev/null || cp "$OUT_DMG" "$STAGE/$DMG_ASSET"
ln "$OUT_TAR" "$STAGE/$TAR_ASSET" 2>/dev/null || cp "$OUT_TAR" "$STAGE/$TAR_ASSET"
ln "$OUT_TAR.sig" "$STAGE/$SIG_ASSET" 2>/dev/null || cp "$OUT_TAR.sig" "$STAGE/$SIG_ASSET"
ln "$OUT_FEED" "$STAGE/latest.json" 2>/dev/null || cp "$OUT_FEED" "$STAGE/latest.json"
(cd "$STAGE" && shasum -a 256 "$DMG_ASSET" "$TAR_ASSET") > "$STAGE/SHA256SUMS.txt"
BODY="$WORK/release-notes.md"
{
  if [ -n "$NOTES_FILE" ]; then cat "$NOTES_FILE"; else echo "$APP_NAME $V."; fi
  echo
  echo "**$DMG_ASSET**: macOS, Apple silicon. Developer ID signed (team $TEAM), notarized and stapled (the app and the disk image)."
  echo
  echo "**$TAR_ASSET**, **.sig** and **latest.json**: the signed update for the updater in the app. You do not need to download them."
} > "$BODY"
verify_assets "$STAGE" local || die "the local release files failed $FAILS check(s)"

if [ "$RESUME" = 1 ]; then
  gh release edit "$TAG" -R "$REPO" --title "$APP_NAME $V" --notes-file "$BODY" >/dev/null
else
  gh release create "$TAG" -R "$REPO" --draft --target "$SHA" --title "$APP_NAME $V" --notes-file "$BODY" >/dev/null
  TAG_STATE="The draft $TAG stays a draft (gh release delete $TAG -R $REPO removes it)."
fi
# GitHub's release list can lag a few seconds behind a draft that was just made: ask up to 6 times.
REL_ID=""
for _try in 1 2 3 4 5 6; do
  REL_ID="$(gh api "repos/$REPO/releases?per_page=100" --paginate -q ".[] | select(.tag_name == \"$TAG\" and .draft) | .id")"
  [ -n "$REL_ID" ] && break
  sleep 10
done
[ -n "$REL_ID" ] && [ "$(printf '%s\n' "$REL_ID" | wc -l | tr -d ' ')" = 1 ] || die "could not find the one draft $TAG"
REMOTE="$(gh api "repos/$REPO/releases/$REL_ID" -q '.assets[] | "\(.name) \(.digest)"')"
for a in "${ASSETS[@]}"; do
  if printf '%s\n' "$REMOTE" | grep -q -x -F "$a sha256:$(sha_of "$STAGE/$a")"; then
    echo "  on the draft already: $a"
  else
    gh release upload "$TAG" -R "$REPO" "$STAGE/$a" --clobber
    echo "  uploaded: $a"
  fi
done
while read -r name _; do
  [ -n "$name" ] || continue
  printf '%s\n' "${ASSETS[@]}" | grep -q -x -F "$name" || { gh release delete-asset "$TAG" "$name" -R "$REPO" -y; echo "  removed an asset that is not part of the release: $name"; }
done <<< "$REMOTE"

# ---------------------------------------------------------------------------------------------
step "5/6 Download the draft into an empty folder and verify it"
CHECK="$WORK/download"
rm -rf "$CHECK"; mkdir -p "$CHECK"
gh release download "$TAG" -R "$REPO" -D "$CHECK"
PASSES=0
for a in "${ASSETS[@]}"; do
  check "downloaded $a = the local file" "$(sha_of "$CHECK/$a" 2>/dev/null | cut -c1-12)" test "$(sha_of "$CHECK/$a")" = "$(sha_of "$STAGE/$a")"
done
DL_FAILS="$FAILS"
verify_assets "$CHECK" download && [ "$DL_FAILS" = 0 ] || die "the downloaded draft failed a check"
rm -rf "$CHECK"
echo "  The draft $TAG passed all $PASSES checks."

if [ "$DRAFT_ONLY" = 1 ]; then
  echo
  echo "Draft verified, not published (--draft-only): https://github.com/$REPO/releases (draft $TAG)."
  echo "Publish it with the same command without --draft-only."
  exit 0
fi

# ---------------------------------------------------------------------------------------------
step "6/6 Publish $TAG"
gh release edit "$TAG" -R "$REPO" --draft=false --latest >/dev/null
TAG_STATE=""
FAILS=0
check "the release is public" "" test "$(gh release view "$TAG" -R "$REPO" --json isDraft -q .isDraft)" = false
check "the tag $TAG is on $SHA" "" test "$(git ls-remote --tags origin "refs/tags/$TAG" | cut -f1)" = "$SHA"
for a in "${ASSETS[@]}"; do
  code="$(curl -sSIL -o /dev/null -w '%{http_code}' "$BASE_URL$a" || true)"
  check "public URL answers 200: $a" "$code" test "$code" = 200
done
check "the public latest.json is the verified one" "" test "$(curl -fsSL "${BASE_URL}latest.json" | shasum -a 256 | cut -d' ' -f1)" = "$(sha_of "$STAGE/latest.json")"
echo
echo "Released: https://github.com/$REPO/releases/tag/$TAG"
echo "publik takes in new GitHub releases once a day at 10:00 UTC. After that, $FEED_URL serves $V."
if [ "$KEEP" = 0 ]; then
  rm -rf "$WORK" "$OUT_APP" "$BUNDLE/updater" "$BUNDLE/dmg"
  echo "Removed the local work files (the release assets are on GitHub)."
fi
[ "$FAILS" = 0 ] || { echo "The release is public, but $FAILS check(s) after publishing failed (see above)." >&2; exit 1; }
