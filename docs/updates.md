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

- `.github/workflows/publik-build.yml` (CI) builds the app: `tauri build --bundles app`, signed
  ad hoc, with the publik app token (repo secret `PUBLIK_APP_TOKEN`) compiled in. It makes no
  updater artifacts (`createUpdaterArtifacts: false`) and needs no update key. Its app is never
  an update by itself.
- `scripts/build-macos.sh --app <that app>` (release Mac) signs it with the Developer ID (inner
  code first, hardened runtime, `src-tauri/entitlements.plist`, secure timestamp), notarizes and
  staples it, then `scripts/updater-pack-macos.sh` packs and signs that stapled app with the key
  from the login keychain, `scripts/updater-latest-json.mjs` writes `latest.json`, and the dmg is
  made, notarized and stapled. The script unsets `TAURI_SIGNING_PRIVATE_KEY*`, so the key comes
  from the keychain only. Without `--app` it builds the app locally with `tauri build` first.
- `scripts/publik-release.sh` runs both, and everything around them (next section).
- Any other build: `tauri build` without the key fails while `createUpdaterArtifacts` is on.
  Add `--config '{"bundle":{"createUpdaterArtifacts":false}}'`.

## Cut a release

One command on the release Mac. It does the whole release: there is nothing to do by hand
between its steps.

1. Set the new version in `src-tauri/tauri.conf.json`, `src-tauri/Cargo.toml`, the `plantgpt`
   entry of `src-tauri/Cargo.lock`, `package.json` and `package-lock.json` (`version` and
   `packages[""].version`). Commit and push to `main`.
2. Write the release notes to a file (outside the repo is fine). They go at the top of the
   release text and into `latest.json`.
3. In a clean checkout of `main` on the release Mac:
   ```sh
   scripts/publik-release.sh <version> --notes-file notes.md
   ```

| Step | What `scripts/publik-release.sh` does | Stops when |
|---|---|---|
| 1. Checks | `main`, a clean tree equal to `origin/main`, the version in all six places, higher than the last release, tag `v<version>` free (or a draft of this commit, which it resumes), the Developer ID identity, the `publik` notarytool profile, the `publik-update-key` items (not read), gh, node, the Tauri CLI, 1.5 GB free disk | any check fails |
| 2. CI build | runs `publik-build.yml` on this commit (or reuses a successful run of the same commit), waits, downloads the app, checks version, arm64, bundle id, feed URL and that the app token is the one of the last release | the run fails or the app is wrong |
| 3. Sign | `scripts/build-macos.sh --app`: Developer ID signing, notarization (`notarytool --keychain-profile publik --wait`, only "Accepted" passes), staple, update bundle + `.sig`, `latest.json` with absolute GitHub URLs, dmg (signed, notarized, stapled) | Apple does not accept, a signature does not verify |
| 4. Draft | a DRAFT release `v<version>` on this commit with `plantgpt-<v>-macos-arm64.dmg`, `PlantGPT_<v>_aarch64.app.tar.gz`, its `.sig`, `latest.json`, `SHA256SUMS.txt` (the same names as before: publik's listing links the dmg, `latest.json` names the `.tar.gz`) | |
| 5. Verify | downloads the draft into an empty folder and checks it: the feed signature with the public key of this commit AND of the last release (what installed copies check), the version it signs, hashes, Info.plist version = feed = tag, codesign (deep, strict), Developer ID + team, hardened runtime, timestamp, stapled tickets, Gatekeeper on quarantined copies of the app and the dmg ("Notarized Developer ID"), the dmg's app = the update bundle's app (cdhash), designated requirement, entitlements and app token the same as the last release, no test feed compiled in, `scripts/verify-macos.sh --require-notarized --no-launch` | any check fails: the release stays a draft |
| 6. Publish | publishes the draft, then checks the tag, the five public URLs (200) and the public `latest.json` | |

- Run the same command again after a failure. It keeps what is done and still valid (the CI run,
  the signed and notarized files, the draft and the assets already on it, by SHA-256), checks it
  again and runs the rest.
- `--draft-only` stops after step 5. Run the command again without it to publish.
- `--verify <dir>` runs only the step-5 checks on the assets of a release in `<dir>` (for example
  `gh release download v0.1.3 -D dir`), against the release before it.
- It starts no app (no window on the release Mac) and prints no secret: the update key goes from
  the keychain to `tauri signer sign` only. macOS may ask once to let `security` read the key.
- The work files are in `src-tauri/target/publik-release/v<version>` and the build output in
  `src-tauri/target/release/bundle`; both are removed after publishing (`--keep` keeps them).
- No `npm ci` and no local cargo build: without `node_modules`, the script runs the Tauri CLI of
  `package.json` through `npx` for `tauri signer sign`.

publik takes in new GitHub releases once a day at 10:00 UTC. Installed copies update after
that, when `https://publikhq.com/api/updates/plantgpt/latest.json` serves the new version.

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
   `scripts/publik-release.sh` checks the feed signature with the key of the commit and with the
   key of the last release, so it refuses this bridge release: make it by hand.
3. From the next release on, sign with the new key. Copies that skipped the bridge release can
   still update only to a release signed with the old key, so keep the old key until you accept
   that those copies stop updating.
4. If the private key leaks, cut the bridge release at once. A leaked key alone cannot push an
   update: the attacker must also control the feed on publikhq.com.

## Test

### Live proof: a release, the live feed, real permissions

Run `live-update-proof.yml` (workflow_dispatch, inputs `from_tag` and `expect_version`):

```sh
gh workflow run live-update-proof.yml -f from_tag=v0.1.3 -f expect_version=0.1.4
```

On `macos-latest` it downloads the dmg of `from_tag` (the asset publik's listing links),
quarantines it as a browser does, checks Gatekeeper ("Notarized Developer ID"), opens the dmg and
drags the app onto Applications in its Finder window (a real mouse drag, as a person installs it),
records the designated requirement and writes real TCC grants (camera, microphone, screen capture,
accessibility) with a csreq made from it. Then it starts the app with `open`, answers Gatekeeper's
first-launch question with "Open" and quits it, and starts it again for the test: the app must run
from /Applications, not from an App Translocation folder. The release build asks the live feed;
there is no test hook and no feed override. Nobody signs in: the launchd environment points the
sign-in gate's `PUBLIK_ORIGIN` at a closed local port, so a runner registers no installs on
publik, and the updater does not read that origin. The job waits for the updater, answers
"Restart" (and after a second clean install "Later", then "Restart" from the menu), and checks the
version on disk, the binary of the running process and the app's own answer to PlantGPT > Check
for Updates… ("PlantGPT <v> is the latest version."). After the update it checks the designated
requirement, Gatekeeper and, for each TCC grant, that the updated app satisfies the stored csreq.
That is the check tccd makes; a runner cannot show a consent prompt, so this is the proof that no
new prompt is needed. A pktap capture shows which process asked publikhq.com and GitHub.

With `expect_version` = the version of `from_tag` (the feed still serves that version), the app
must report "no update" and stay on it: the harness check before a new release is public.
The `unit-tests` job runs the updater unit tests, among them the 24-hour timer on a paused tokio
clock (`cargo test updates::`).

### Signatures, with a local feed

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
