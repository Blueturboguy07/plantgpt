# Updates

PlantGPT updates itself with `tauri-plugin-updater`. Every update package is signed with the
publik update key. The app checks each package against the public key in
`src-tauri/tauri.conf.json` before it installs anything. PlantGPT ships for macOS (Apple
silicon) only, so the feed has one platform: `darwin-aarch64`.

## How it works

- The app reads `https://publikhq.com/api/updates/plantgpt/latest.json`. publik serves the
  `latest.json` asset of the scan-approved release tag, byte for byte. publik does not sign or
  change it, so the release `latest.json` must be complete and correct. The route answers 404
  until a scan-approved release carries a `latest.json` asset. A 404 is silent in the background
  check, and a manual check shows it as an error.
- The app checks 10 s after launch and then once a day. It checks before the sign-in gate, so an
  update can fix a gate bug. "Check for Updates…" in the app menu (PlantGPT > Check for
  Updates…) checks at once. `PUBLIK_NO_AUTO_UPDATE=1` turns off the automatic checks (the CI
  workflows and `scripts/verify-macos.sh` set it; set it for `npm run tauri dev` too).
- The app downloads the new `PlantGPT.app`, verifies it, puts it in place of the old one, and
  asks "Restart" or "Later". If the user cannot write to the app's folder, the app does not
  replace it in the background. It asks "Install and Restart" or "Later", and macOS asks for an
  admin password only after "Install and Restart".
- The signature must also name the version that `latest.json` announces
  (`requireSignedVersion`). The app never installs an older version.
- A failed automatic check goes to stderr only. A failed manual check shows the error.
- Code: `src-tauri/src/updates.rs` (copied from GSpot), wired in `src-tauri/src/main.rs`.
  Proof: `.github/workflows/updater-proof.yml`.

Copies of 0.1.2 and older have no updater. Their users must install the first release with the
updater from the dmg once. Later releases reach them through the feed.

## The key

| Where | What |
|---|---|
| Release Mac, login keychain, service `publik-update-key` | `mann-private` (private key), `mann-password` (its password), `mann-public` (public key) |
| GitHub secrets on this repo | `TAURI_SIGNING_PRIVATE_KEY`, `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` (used by `updater-proof.yml` only) |
| `src-tauri/tauri.conf.json` | `plugins.updater.pubkey` (public, key ID `F5E0515C77912BD0`) |

It is the same key as GSpot and the other publik desktop apps. Keep a backup of the private key
and its password. Without them, installed copies can never update again.

## Where the update files are made

The release app is signed with the Developer ID on the release Mac, not in CI. The update
bundle must be the final app (Developer ID signed, notarized, stapled), because the updater
installs exactly those bytes. An update made from any earlier app would replace the user's app
with one that has another code signature, and macOS would drop its permissions (TCC).

- `scripts/build-macos.sh` (release Mac): `tauri build` with `createUpdaterArtifacts` off, then
  notarize and staple the app, then `scripts/updater-pack-macos.sh` packs and signs that stapled
  app with the key from the login keychain, then `scripts/updater-latest-json.mjs` writes
  `latest.json`, then the dmg. The script unsets `TAURI_SIGNING_PRIVATE_KEY*`, so the key comes
  from the keychain only. It stops before the build if the keychain has no key.
- `.github/workflows/publik-build.yml` (CI): an ad-hoc signed check build. It makes no updater
  artifacts (`createUpdaterArtifacts: false`) and needs no update key. Its app is never an
  update. A pipeline that ever re-signs that artifact for a release must run
  `scripts/updater-pack-macos.sh` and `scripts/updater-latest-json.mjs` on the app after
  stapling, as `build-macos.sh` does.
- Any other build: `tauri build` without the key fails while `createUpdaterArtifacts` is on.
  Add `--config '{"bundle":{"createUpdaterArtifacts":false}}'`.

## Cut a release

1. Set the new version in `src-tauri/tauri.conf.json`, `src-tauri/Cargo.toml` and
   `package.json`, run `(cd src-tauri && cargo update -w)` and `npm install --package-lock-only`,
   commit and push.
2. On the release Mac, in a clean checkout of that commit, write the release notes to
   `notes.md` (outside the repo is fine) and build:
   ```sh
   npm ci
   PUBLIK_APP_TOKEN=<the plantgpt app token> scripts/build-macos.sh --notes-file notes.md
   scripts/verify-macos.sh --require-notarized
   ```
   `build-macos.sh` needs the Developer ID identity, the `publik` notarytool profile and the
   `publik-update-key` keychain items. macOS may ask once to let `security` read the key. Out:
   ```
   src-tauri/target/release/bundle/dmg/PlantGPT_<v>_aarch64.dmg
   src-tauri/target/release/bundle/updater/PlantGPT_<v>_aarch64.app.tar.gz
   src-tauri/target/release/bundle/updater/PlantGPT_<v>_aarch64.app.tar.gz.sig
   src-tauri/target/release/bundle/updater/latest.json
   ```
   `latest.json` points at
   `https://github.com/Blueturboguy07/plantgpt/releases/download/v<v>/PlantGPT_<v>_aarch64.app.tar.gz`.
   The script refuses a signature that does not verify with the pubkey or names another version.
3. Make a draft release with all four files. Keep the names of the updater files: `latest.json`
   names the `.app.tar.gz` asset.
   ```sh
   V=<v>; B=src-tauri/target/release/bundle
   (cd "$B" && shasum -a 256 dmg/PlantGPT_${V}_aarch64.dmg updater/PlantGPT_${V}_aarch64.app.tar.gz) > SHA256SUMS.txt
   gh release create "v$V" --draft --title "PlantGPT $V" --notes-file notes.md \
     "$B/dmg/PlantGPT_${V}_aarch64.dmg" \
     "$B/updater/PlantGPT_${V}_aarch64.app.tar.gz" "$B/updater/PlantGPT_${V}_aarch64.app.tar.gz.sig" \
     "$B/updater/latest.json" SHA256SUMS.txt
   ```
4. Publish the release (`gh release edit "v$V" --draft=false`). Check that the asset URL in
   `latest.json` answers 200 (`curl -fsIL <url>`). Installed copies update when publik approves
   the release and serves its `latest.json`.

## Roll back

The app installs only a version higher than its own. You cannot push an older version.

1. Stop the bad release at once: withdraw it in publik, or delete its `latest.json` asset.
   Copies that did not update yet stay on the old version.
2. Revert the bad change, give it a higher version (for example 0.1.5 after a bad 0.1.4), and cut
   a release. Copies on the bad version update to it.

Do not turn on `allowDowngrades`. It removes the only guard against an old, signed release
served as a new one.

## Rotate the key

The public key is compiled into each copy, so a new key reaches users only through an update.

1. Make a new key: `npx tauri signer generate -w new.key`. Store the private key, its password
   and the public key in the keychain items and the repo secrets (new names first, so the old
   key stays available).
2. Put the new public key in `tauri.conf.json`. Release this version signed with the OLD key.
3. From the next release on, sign with the new key. Copies that skipped the bridge release can
   still update only to a release signed with the old key, so keep the old key until you accept
   that those copies stop updating.
4. If the private key leaks, cut the bridge release at once. A leaked key alone cannot push an
   update: the attacker must also control the feed on publikhq.com.

## Test

Run `updater-proof.yml` (workflow_dispatch: `gh workflow run updater-proof.yml --ref <branch>`). It
builds 0.0.1 and 0.0.2 with the `publik-build.yml` command, signs both with one throwaway
certificate (the runner has no Developer ID), installs 0.0.1 on `macos-latest`, and checks that
0.0.1 refuses three bad feeds (another key, one changed byte, a version the signature does not
name) with the app on disk unchanged, and then updates to 0.0.2 with the same bundle id,
certificate and designated requirement. Then it starts 0.0.1 once more and checks that the
restart question is on screen while the app keeps running. It also checks the shipped feed URL,
the release form of `latest.json`, and the order of the steps in `scripts/build-macos.sh`.

The app has a test hook for this: `PUBLIK_UPDATE_SELF_TEST=version|check|install` runs the
updater with no window, no sign-in gate and no prompt, and prints one JSON line. `prompt` runs
the background path and shows the real question. The hook does not click the buttons.
