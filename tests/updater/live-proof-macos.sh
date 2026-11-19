#!/usr/bin/env bash
# Live update proof on a GitHub macOS runner (.github/workflows/live-update-proof.yml). NEVER run it
# on a desk Mac: it installs into /Applications, writes TCC rows, changes the launchd environment
# and starts the app.
#
# Usage: tests/updater/live-proof-macos.sh <from_tag> <expect_version> <out dir>
#
# 1. Downloads the dmg of release <from_tag> (the asset publik's listing links), quarantines it as
#    a browser does, checks Gatekeeper ("Notarized Developer ID"), opens the dmg and drags the app
#    onto Applications in its Finder window (a real mouse drag).
# 2. Records the designated requirement and writes real TCC grants (camera, microphone, screen
#    capture, accessibility) for the bundle id with a csreq made from it.
# 3. Starts the app with `open` (LaunchServices; answers the Gatekeeper question with "Open"). The
#    release build asks the live feed https://publikhq.com/api/updates/plantgpt/latest.json.
#    Nothing in the app is clicked and no one signs in.
# 4. Waits for the updater, answers its question ("Restart", and in a second install "Later"),
#    and checks the version on disk, the running process and the version the app reports.
# 5. Checks the designated requirement, Gatekeeper and every TCC grant's csreq against the app.
# 6. Clicks PlantGPT > Check for Updates… and reads the app's answer.
# With expect_version = the version of from_tag (a harness run while the feed serves N), the app
# must find no update and stay on N.
#
# The sign-in gate's publik origin is set to a closed local port in the launchd environment
# (PUBLIK_ORIGIN), so the runner does not register installs on publik. The updater does not use
# that origin: its feed URL is compiled in from tauri.conf.json.
set -uo pipefail
FROM_TAG="${1:?from_tag}"; EXPECT="${2:?expect_version}"; OUT="${3:?out dir}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPO="${GITHUB_REPOSITORY:-Blueturboguy07/plantgpt}"
BUNDLE_ID="com.mannbellani.plantgpt"
APP=/Applications/PlantGPT.app
FEED="https://publikhq.com/api/updates/plantgpt/latest.json"
N="${FROM_TAG#v}"
UI="$ROOT/tests/updater/ui.applescript"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d)"
RESULTS="$OUT/results.md"
PASS=0; FAILS=0
echo "| Check | Result | Detail |" > "$RESULTS"; echo "|---|---|---|" >> "$RESULTS"
pass() { PASS=$((PASS + 1)); echo "PASS  $1${2:+  ($2)}"; echo "| $1 | PASS | ${2:-} |" >> "$RESULTS"; }
fail() { FAILS=$((FAILS + 1)); echo "FAIL  $1${2:+  ($2)}"; echo "| $1 | **FAIL** | ${2:-} |" >> "$RESULTS"; }
check() { local name="$1" detail="$2"; shift 2; if "$@" >/dev/null 2>&1; then pass "$name" "$detail"; else fail "$name" "$detail"; fi; }
note() { echo "NOTE  $1"; echo "| $1 | note | ${2:-} |" >> "$RESULTS"; }
section() { echo; echo "==> $*"; echo "| **$*** | | |" >> "$RESULTS"; }
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null; }
dr() { codesign -d -r- "$1" 2>&1 | sed -n 's/^designated => //p'; }
cdhash() { codesign -dvvv "$1" 2>&1 | sed -n 's/^CDHash=//p'; }
with_timeout() { local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }
ui() { with_timeout 60 osascript "$UI" "$@" 2>&1; }
SHOT=0
shot() { SHOT=$((SHOT + 1)); local f; f="$OUT/$(printf '%02d' "$SHOT")-$1.png"; screencapture -x "$f" 2>/dev/null || echo "screencapture failed for $1"; }
windows_log() { { echo "--- $(date -u +%H:%M:%S) $1"; ui list; } >> "$OUT/windows.log"; }
# Waits until `ui list` shows a window of <process> whose texts contain <text>; prints that line.
wait_window() {
  local proc="$1" text="$2" secs="$3" line
  for _ in $(seq 1 "$secs"); do
    line="$(ui list | awk -F'\t' -v p="$proc" -v t="$text" '$1 == p && index($3, t) {print; exit}')"
    [ -n "$line" ] && { echo "$line"; return 0; }
    sleep 1
  done
  return 1
}
app_pid() { pgrep -n -f '/PlantGPT\.app/Contents/MacOS/plantgpt' || true; }
running_exe() { lsof -a -p "$1" -d txt -Fn 2>/dev/null | sed -n 's/^n//p' | grep '/Contents/MacOS/' | head -1; }
running_inode() { lsof -a -p "$1" -d txt -Fin 2>/dev/null | awk '/^i/ {i = substr($0, 2)} /^n.*\/Contents\/MacOS\// {print i; exit}'; }
disk_inode() { stat -L -f %i "$APP/Contents/MacOS/$(plist "$APP" CFBundleExecutable)"; }
quit_app() {
  local pid; pid="$(app_pid)"
  [ -n "$pid" ] || return 0
  kill "$pid" 2>/dev/null
  for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || return 0; sleep 1; done
  kill -9 "$pid" 2>/dev/null || true
}
cleanup() {
  quit_app
  [ -n "${TCPDUMP:-}" ] && sudo kill -INT "$TCPDUMP" 2>/dev/null
  launchctl unsetenv PUBLIK_ORIGIN 2>/dev/null; launchctl unsetenv DO_NOT_TRACK 2>/dev/null
  [ -n "${MNT:-}" ] && hdiutil detach "$MNT" -quiet 2>/dev/null
  true
}
trap cleanup EXIT

UPDATE=1; [ "$EXPECT" = "$N" ] && UPDATE=0
section "Runner"
{ sw_vers; uname -m; csrutil status 2>&1; spctl --status 2>&1; } | tee "$OUT/runner.txt"
echo "from $FROM_TAG ($N), expect $EXPECT, update expected: $UPDATE"

# Gatekeeper must be on, or spctl would accept anything ("override=security disabled").
if ! spctl --status 2>&1 | grep -q 'assessments enabled'; then
  sudo spctl --master-enable 2>/dev/null || sudo spctl --global-enable 2>/dev/null || true
fi
check "Gatekeeper assessments are on" "$(spctl --status 2>&1)" sh -c "spctl --status 2>&1 | grep -q 'assessments enabled'"

# The gate must not register installs on publik from a runner; the updater does not read PUBLIK_ORIGIN.
launchctl setenv PUBLIK_ORIGIN "http://127.0.0.1:9"
launchctl setenv DO_NOT_TRACK 1

# UI scripting needs accessibility (and Apple events to System Events) for the runner's processes.
# Runner images grant it; if they do not, grant it here and say so.
UI_PROBE="$(ui list)"
if printf '%s' "$UI_PROBE" | grep -q -E '\-1719|\-1743|\-25211|not allowed|assistive'; then
  note "UI scripting was refused; granting accessibility to the runner's shells and osascript" "$UI_PROBE"
  for client in /usr/bin/osascript /bin/bash /bin/zsh /bin/sh /usr/libexec/sshd-keygen-wrapper; do
    sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
      "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier, flags) VALUES ('kTCCServiceAccessibility', '$client', 1, 2, 4, 1, 'UNUSED', 0);" || true
    sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
      "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier_type, indirect_object_identifier, flags) VALUES ('kTCCServiceAppleEvents', '$client', 1, 2, 4, 1, 0, 'com.apple.systemevents', 0);" || true
  done
  UI_PROBE="$(ui list)"
fi
echo "$UI_PROBE" > "$OUT/windows.log"
check "UI scripting works (System Events)" "$(printf '%s' "$UI_PROBE" | head -c 120)" \
  sh -c "! printf '%s' \"\$1\" | grep -q -E 'execution error|\\-1719|\\-1743|\\-25211'" _ "$UI_PROBE"
shot desktop-before

section "The live feed"
curl -fsSL "$FEED" -o "$OUT/feed-before.json"
FEED_VERSION="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$OUT/feed-before.json" 2>/dev/null)"
check "the live feed answers and serves $EXPECT" "$FEED $FEED_VERSION" test "$FEED_VERSION" = "$EXPECT"

section "Clean download of $FROM_TAG"
ASSET="$(gh release view "$FROM_TAG" -R "$REPO" --json assets -q '[.assets[] | select(.name | endswith(".dmg"))] | if length == 1 then .[0].name else empty end')"
DIGEST="$(gh release view "$FROM_TAG" -R "$REPO" --json assets -q ".assets[] | select(.name == \"$ASSET\") | .digest")"
URL="https://github.com/$REPO/releases/download/$FROM_TAG/$ASSET"
[ -n "$ASSET" ] || { fail "release $FROM_TAG has exactly one dmg"; echo "$PASS passed, $FAILS failed"; exit 1; }
DMG="$HOME/Downloads/$ASSET"
rm -f "$DMG"; mkdir -p "$HOME/Downloads"
ls -la "$HOME/Downloads" > "$OUT/downloads-before.txt"
curl -fsSL -o "$DMG" "$URL"
check "the release has one dmg and it downloads" "$URL" test -f "$DMG" -a -s "$DMG"
check "the download is the release asset (sha256)" "$DIGEST" test "sha256:$(shasum -a 256 "$DMG" | cut -d' ' -f1)" = "$DIGEST"
# What Safari writes on a download.
xattr -w com.apple.quarantine "0083;$(printf %x "$(date +%s)");Safari;$(uuidgen)" "$DMG"
GK_DMG="$(spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1)"; echo "$GK_DMG" > "$OUT/spctl-dmg.txt"
check "Gatekeeper accepts the quarantined dmg: Notarized Developer ID" "$(echo "$GK_DMG" | tr '\n' ' ')" \
  sh -c "printf '%s\n' \"\$1\" | grep -q ': accepted' && printf '%s\n' \"\$1\" | grep -q -x 'source=Notarized Developer ID'" _ "$GK_DMG"

# The mount point of the dmg, if it is mounted.
dmg_mount() {
  hdiutil info -plist | python3 -I -c '
import os, plistlib, sys
want = os.path.realpath(sys.argv[1])
for i in plistlib.loads(sys.stdin.buffer.read()).get("images", []):
    if os.path.realpath(i.get("image-path", "")) == want:
        for e in i.get("system-entities", []):
            if e.get("mount-point"):
                print(e["mount-point"]); sys.exit()
' "$DMG"
}

# A real mouse drag (CGEvent), as a person drags the app icon onto the Applications icon.
DRAG="$WORK/drag"
swiftc -O "$ROOT/tests/updater/drag.swift" -o "$DRAG" > "$OUT/drag-build.log" 2>&1 || echo "swiftc failed: $(tail -3 "$OUT/drag-build.log")"
# Posting mouse events needs accessibility, as UI scripting does (the runner's processes have it).
for svc in kTCCServiceAccessibility kTCCServicePostEvent; do
  sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
    "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier, flags) VALUES ('$svc', '$DRAG', 1, 2, 4, 1, 'UNUSED', 0);" || true
done

# Install N as a person does: double-click the downloaded dmg (DiskImageMounter mounts it; Gatekeeper
# checks it), drag PlantGPT onto Applications in the dmg's Finder window, eject the dmg. If the drag
# does not copy the app, a Finder copy by AppleScript is the fallback, and the check says so.
INSTALL_METHOD=""
install_n() {
  local i vol icons from to q
  quit_app
  sudo rm -rf "$APP"
  open "$DMG"
  MNT=""
  for i in $(seq 1 90); do
    MNT="$(dmg_mount)"; [ -n "$MNT" ] && break
    sleep 1
  done
  [ -n "$MNT" ] || { windows_log "the dmg did not mount"; shot dmg-not-mounted; fail "the dmg mounts (double-click: open)"; return 1; }
  vol="$(basename "$MNT")"
  echo "mounted at $MNT ($(mount | grep -F " on $MNT " | sed 's/.*(//; s/)$//'))"
  # The dmg window opens by itself when the dmg asks for it; otherwise a person opens the volume.
  icons=""; local t_end=$((SECONDS + 90)) opened=no
  while [ "$SECONDS" -lt "$t_end" ]; do
    icons="$(ui icons "$vol")"
    printf '%s\n' "$icons" | awk -F'\t' '$1 == "finder" && $2 == "Applications"' | grep -q . && break
    [ "$opened" = no ] && [ "$SECONDS" -gt $((t_end - 75)) ] && { open "$MNT"; opened=yes; }
    sleep 2
  done
  icons="$icons"$'\n'"$(ui axdump "$vol")"
  printf '%s\n' "$icons" > "$OUT/dmg-window-ui.txt"
  shot dmg-window
  # Where to press and where to let go, in screen points: the accessibility element of the icon if
  # it has one, else Finder's icon position plus the screen position of the window's content
  # (its scroll area, else the window below a 28-point title bar).
  row() { printf '%s\n' "$icons" | awk -F'\t' -v k="$1" -v re="$2" '$1 == k && $2 ~ re {print $3, $4; exit}'; }
  at() {
    local p o
    p="$(row ax:AXImage "$1")"; [ -n "$p" ] && { echo "$p"; return; }
    p="$(row finder "$1")"; [ -n "$p" ] || return 0
    o="$(row content '.')"
    [ -n "$o" ] || { o="$(row window '.')"; [ -n "$o" ] && o="${o% *} $(( ${o#* } + 28 ))"; }
    [ -n "$o" ] || return 0
    echo "$(( ${o% *} + ${p% *} )) $(( ${o#* } + ${p#* } ))"
  }
  from="$(at '^PlantGPT(\\.app)?$')"
  to="$(at '^Applications$')"
  echo "dmg window: $(printf '%s' "$icons" | grep -v '^ax:' | tr '\n\t' '; ')"
  echo "drag from ($from) to ($to)"
  INSTALL_METHOD=""
  if [ -n "$from" ] && [ -n "$to" ] && [ -x "$DRAG" ]; then
    with_timeout 20 osascript -e 'tell application "Finder" to activate' >/dev/null 2>&1
    sleep 1
    # shellcheck disable=SC2086 # two numbers each
    "$DRAG" $from $to
    for i in $(seq 1 60); do
      [ -d "$APP" ] && codesign --verify --deep --strict "$APP" >/dev/null 2>&1 && { INSTALL_METHOD="Finder drag from the dmg window onto Applications"; break; }
      sleep 1
    done
    shot after-drag
  fi
  if [ -z "$INSTALL_METHOD" ]; then
    windows_log "the drag did not copy the app (icons: $(printf '%s' "$icons" | tr '\n\t' '; '))"
    sudo rm -rf "$APP"
    if with_timeout 60 osascript -e "set src to (POSIX file \"$MNT/PlantGPT.app\") as alias" -e 'set dst to (POSIX file "/Applications") as alias' \
        -e 'tell application "Finder" to duplicate src to dst with replacing' >/dev/null 2>"$WORK/finder.err"; then
      INSTALL_METHOD="Finder copy by AppleScript (FALLBACK: the drag did not copy the app)"
    else
      INSTALL_METHOD="ditto (FALLBACK: drag and Finder copy failed: $(head -c 120 "$WORK/finder.err"))"
      ditto "$MNT/PlantGPT.app" "$APP"
    fi
  fi
  hdiutil detach "$MNT" -quiet || hdiutil detach "$MNT" -force -quiet; MNT=""
  q="$(xattr -p com.apple.quarantine "$APP" 2>/dev/null)"
  if [ -z "$q" ]; then
    # The copy lost the quarantine: put the dmg's back, so the first launch is a user's first launch.
    xattr -w com.apple.quarantine "$(xattr -p com.apple.quarantine "$DMG")" "$APP"
    note "the installed copy had no quarantine attribute; set it from the dmg" "$(xattr -p com.apple.quarantine "$APP")"
  fi
  case "$INSTALL_METHOD" in
    Finder\ drag*) pass "installed $N by a Finder drag from the dmg window onto Applications" "quarantine $(xattr -p com.apple.quarantine "$APP" 2>/dev/null)" ;;
    *) fail "installed $N by a Finder drag from the dmg window onto Applications" "$INSTALL_METHOD" ;;
  esac
  check "the installed app is $N" "version $(plist "$APP" CFBundleShortVersionString)" test "$(plist "$APP" CFBundleShortVersionString)" = "$N"
  local gk; gk="$(spctl -a -t exec -vv "$APP" 2>&1)"; echo "$gk" >> "$OUT/spctl-app.txt"
  check "Gatekeeper accepts the installed, quarantined app: Notarized Developer ID" "$(echo "$gk" | tr '\n' ' ')" \
    sh -c "printf '%s\n' \"\$1\" | grep -q ': accepted' && printf '%s\n' \"\$1\" | grep -q -x 'source=Notarized Developer ID'" _ "$gk"
  check "the installed app's signature is intact and stapled" "" sh -c "codesign --verify --deep --strict '$APP' && xcrun stapler validate '$APP'"
}

# Writes the summary and ends the run with the result.
finish() {
  echo
  echo "$PASS passed, $FAILS failed"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    { echo "### Live update proof: $FROM_TAG -> $EXPECT on $(sw_vers -productVersion) $(uname -m): $PASS passed, $FAILS failed"; echo; cat "$RESULTS"; } >> "$GITHUB_STEP_SUMMARY"
  fi
  [ "$FAILS" -eq 0 ]; exit
}

section "Install $FROM_TAG"
install_n || { note "the install failed: the run stops here"; finish; }
DR_BEFORE="$(dr "$APP")"; CDHASH_N="$(cdhash "$APP")"
{ codesign -dvvv "$APP" 2>&1; codesign -d -r- "$APP" 2>&1; } > "$OUT/codesign-before.txt"
echo "designated requirement: $DR_BEFORE"
check "recorded the designated requirement" "$DR_BEFORE" test -n "$DR_BEFORE"

section "TCC grants for $BUNDLE_ID (camera, microphone, screen capture, accessibility)"
USER_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
SYS_DB="/Library/Application Support/com.apple.TCC/TCC.db"
printf '%s' "$DR_BEFORE" | csreq -r- -b "$WORK/csreq.bin"
CSREQ_HEX="$(xxd -p "$WORK/csreq.bin" | tr -d '\n')"
check "csreq blob made from the designated requirement" "$(wc -c < "$WORK/csreq.bin" | tr -d ' ') bytes" test -n "$CSREQ_HEX"
sqlite3 "$USER_DB" '.schema access' > "$OUT/tcc-schema-user.sql" 2>&1
# shellcheck disable=SC2024 # the output file is the runner user's
sudo sqlite3 "$SYS_DB" '.schema access' > "$OUT/tcc-schema-system.sql" 2>&1
grant() { # <db> <sudo|""> <service> <auth_reason>
  local db="$1" su="$2" service="$3" reason="$4" cols names=() values=() c
  cols="$($su sqlite3 "$db" "SELECT name FROM pragma_table_info('access');")"
  for c in $cols; do
    case "$c" in
      service) names+=("$c"); values+=("'$service'") ;;
      client) names+=("$c"); values+=("'$BUNDLE_ID'") ;;
      client_type) names+=("$c"); values+=("0") ;;
      auth_value) names+=("$c"); values+=("2") ;;
      auth_reason) names+=("$c"); values+=("$reason") ;;
      auth_version) names+=("$c"); values+=("1") ;;
      allowed) names+=("$c"); values+=("1") ;;
      prompt_count) names+=("$c"); values+=("1") ;;
      csreq) names+=("$c"); values+=("X'$CSREQ_HEX'") ;;
      indirect_object_identifier_type) names+=("$c"); values+=("0") ;;
      indirect_object_identifier) names+=("$c"); values+=("'UNUSED'") ;;
      flags) names+=("$c"); values+=("0") ;;
      last_modified) names+=("$c"); values+=("CAST(strftime('%s','now') AS INTEGER)") ;;
    esac
  done
  local sql; sql="INSERT OR REPLACE INTO access ($(IFS=,; echo "${names[*]}")) VALUES ($(IFS=,; echo "${values[*]}"));"
  echo "$service -> $db: $sql" >> "$OUT/tcc-writes.txt"
  $su sqlite3 "$db" "$sql"
}
# Where macOS keeps each grant: camera and microphone per user, screen capture and accessibility
# in the system database. auth_value 2 = allowed; auth_reason 2 = the user answered the prompt,
# 3 = the user turned it on in System Settings.
grant "$USER_DB" "" kTCCServiceCamera 2
grant "$USER_DB" "" kTCCServiceMicrophone 2
grant "$SYS_DB" sudo kTCCServiceScreenCapture 3
grant "$SYS_DB" sudo kTCCServiceAccessibility 3
GRANTS="kTCCServiceCamera:user kTCCServiceMicrophone:user kTCCServiceScreenCapture:system kTCCServiceAccessibility:system"
# Each stored grant: present, allowed, and its csreq satisfied by the app on disk (what tccd checks).
tcc_check() {
  local when="$1" g service where db su row hex auth req
  for g in $GRANTS; do
    service="${g%%:*}"; where="${g##*:}"
    if [ "$where" = user ]; then db="$USER_DB"; su=""; else db="$SYS_DB"; su="sudo"; fi
    row="$($su sqlite3 -separator '|' "$db" "SELECT auth_value, hex(csreq) FROM access WHERE service='$service' AND client='$BUNDLE_ID' AND client_type=0;")"
    auth="${row%%|*}"; hex="${row#*|}"
    echo "$when $service ($where db): auth_value=$auth csreq=${hex:0:24}…" >> "$OUT/tcc-rows.txt"
    check "[$when] TCC $service row is there and allowed ($where db)" "auth_value=$auth" test "$auth" = 2
    printf '%s' "$hex" | xxd -r -p > "$WORK/stored.bin"
    req="$(csreq -r "$WORK/stored.bin" -t 2>&1)"
    check "[$when] the stored csreq of $service is satisfied by the app" "$req" codesign --verify -R="$req" "$APP"
  done
}
tcc_check "before"

section "Network capture (pktap: every TLS connection with its process)"
# shellcheck disable=SC2024 # the log file is the runner user's
sudo tcpdump -i pktap -n -s 0 -w "$OUT/net.pcapng" 'tcp dst port 443' > "$OUT/tcpdump.log" 2>&1 &
TCPDUMP=$!
sleep 3
check "tcpdump runs on pktap" "pid $TCPDUMP" kill -0 "$TCPDUMP"

# ------------------------------------------------------------------------------------------------
# Starts the installed app with `open` (LaunchServices, as a double-click does). On the first launch
# of a quarantined app, Gatekeeper holds the new process and asks "“PlantGPT” is an app downloaded
# from the Internet. Are you sure you want to open it?"; this answers "Open". $1: a name for the
# stdout/stderr files, or "" for none. Sets PID and GK_ASKED.
launch_app() {
  local name="$1" i pid=""
  GK_ASKED=no
  if [ -n "$name" ]; then
    open --stdout "$OUT/$name-stdout.log" --stderr "$OUT/$name-stderr.log" "$APP" > "$OUT/$name-open.log" 2>&1 &
  else
    open "$APP" > /dev/null 2>&1 &
  fi
  for i in $(seq 1 60); do
    if ui list | grep -q '^CoreServicesUIAgent.*downloaded from the Internet'; then
      windows_log "Gatekeeper question"; shot "${name:-first-run}-gatekeeper-question"
      [ "$(ui click CoreServicesUIAgent 'downloaded from the Internet' Open)" = "clicked Open" ] && GK_ASKED=yes
      sleep 2; continue
    fi
    pid="$(app_pid)"
    # Without a question the process runs at once; give the question 8 s to show.
    if [ -n "$pid" ] && { [ "$GK_ASKED" = yes ] || [ "$i" -ge 8 ]; }; then break; fi
    sleep 1
  done
  PID="$(app_pid)"
}

# The first launch after an install: the person answers Gatekeeper's question with "Open". The app
# is quit at once, before its first update check (10 s after launch), as for a person who installed
# N earlier and used it: the update test is the next launch. macOS marks the approved app (quarantine
# flags 0x40 "approved", and 0x100 when it was moved out of the folder it arrived in).
first_run() {
  local q exe
  launch_app ""
  exe="$( [ -n "$PID" ] && running_exe "$PID")"
  check "first launch: Gatekeeper asks \"… downloaded from the Internet …\" and \"Open\" answers it" "pid ${PID:-none}, ran from $exe" \
    test "$GK_ASKED/${PID:+running}" = "yes/running"
  quit_app; sleep 3
  q="$(xattr -p com.apple.quarantine "$APP" 2>/dev/null)"
  note "after the approved first launch: quarantine $q" "first launch ran from $exe"
}

# One run of the app: launch the installed N, wait for the updater, answer its question.
#   $1 name, $2 answer to the update question: Restart | Later
run_variant() {
  local name="$1" answer="$2" pid line new t0 log
  log="$OUT/$name-stderr.log"
  if [ "$UPDATE" = 1 ]; then section "Variant $name: start the installed $N with open, then answer \"$answer\""
  else section "Variant $name: start the installed $N with open (no update expected)"; fi
  first_run
  t0="$(date +%s)"
  launch_app "$name"
  pid="$PID"
  check "[$name] the app started (open)" "pid ${pid:-none}" test -n "$pid"
  [ "$GK_ASKED" = no ] || note "[$name] Gatekeeper asked again on the second launch (answered Open)"
  [ -n "$pid" ] || return 1
  local exe; exe="$(running_exe "$pid")"
  check "[$name] it runs from /Applications (not translocated, so the update can replace it in place)" "$exe" \
    test "$exe" = "$APP/Contents/MacOS/$(plist "$APP" CFBundleExecutable)"
  sleep 3; windows_log "$name launched"; shot "$name-launched"

  # The updater: first check 10 s after launch (src-tauri/src/updates.rs), on stderr.
  line=""
  for _ in $(seq 1 150); do
    line="$(grep -m1 '^updates: ' "$log" 2>/dev/null || true)"
    [ -n "$line" ] && break
    sleep 1
  done
  echo "updater: ${line:-(nothing after 150 s)}"
  if [ "$UPDATE" = 0 ]; then
    check "[$name] the updater asked the live feed: no newer version" "$line" test "$line" = "updates: $N is the latest version"
    sleep 5; windows_log "$name after the check"
    check "[$name] no update question" "" sh -c "! osascript '$UI' list | grep -q -E 'is installed|is ready'"
    check "[$name] the app keeps running" "pid $pid" kill -0 "$pid"
    check "[$name] the app on disk is unchanged (cdhash)" "$(cdhash "$APP")" test "$(cdhash "$APP")" = "$CDHASH_N"
    new="$pid"
  else
    check "[$name] the updater downloaded, verified and installed $EXPECT" "$line" test "$line" = "updates: PlantGPT $EXPECT is ready"
    check "[$name] the app on disk is $EXPECT (Info.plist) while $N still runs" "$(plist "$APP" CFBundleShortVersionString), pid $pid" \
      sh -c "test '$(plist "$APP" CFBundleShortVersionString)' = '$EXPECT' && kill -0 $pid"
    check "[$name] the running process is still the old binary (inode)" "running $(running_inode "$pid"), disk $(disk_inode)" \
      test "$(running_inode "$pid")" != "$(disk_inode)"
    line="$(wait_window UserNotificationCenter "PlantGPT $EXPECT is installed" 60)"
    windows_log "$name update question"; shot "$name-update-question"
    check "[$name] the restart question is on screen" "$(echo "$line" | cut -f3-4)" \
      sh -c "printf '%s' \"\$1\" | grep -q 'Restart' && printf '%s' \"\$1\" | grep -q 'Later'" _ "$line"
    if [ "$answer" = Later ]; then
      check "[$name] clicked Later" "" test "$(ui click UserNotificationCenter "is installed" Later)" = "clicked Later"
      sleep 15; windows_log "$name after Later"; shot "$name-after-later"
      check "[$name] after Later the app keeps running as $N (same process)" "pid $pid" kill -0 "$pid"
      check "[$name] after Later no restart happened" "$(app_pid)" test "$(app_pid)" = "$pid"
      # The menu item offers the downloaded update again.
      check "[$name] PlantGPT > Check for Updates… clicked" "" sh -c "osascript '$UI' menu '$BUNDLE_ID' 'Check for Updates' | grep -q '^clicked'"
      line="$(wait_window UserNotificationCenter "PlantGPT $EXPECT is installed" 30)"
      windows_log "$name menu after Later"; shot "$name-menu-offers-restart"
      check "[$name] the menu item offers the restart into $EXPECT again" "$(echo "$line" | cut -f3)" test -n "$line"
    fi
    check "[$name] clicked Restart" "" test "$(ui click UserNotificationCenter "is installed" Restart)" = "clicked Restart"
    for _ in $(seq 1 60); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    new=""
    for _ in $(seq 1 60); do new="$(app_pid)"; [ -n "$new" ] && [ "$new" != "$pid" ] && break; sleep 1; done
    check "[$name] the old process quit and the app started again" "old $pid, new ${new:-none}" sh -c "[ -n '$new' ] && [ '$new' != '$pid' ] && ! kill -0 $pid"
    [ -n "$new" ] || return 1
    check "[$name] the new process runs the $EXPECT binary on disk (inode)" "running $(running_inode "$new"), disk $(disk_inode)" \
      test "$(running_inode "$new")" = "$(disk_inode)"
    sleep 5; windows_log "$name restarted"; shot "$name-restarted"
  fi

  # PlantGPT > Check for Updates…: the answer of the running process (its own version).
  check "[$name] PlantGPT > Check for Updates… clicked" "" sh -c "osascript '$UI' menu '$BUNDLE_ID' 'Check for Updates' | grep -q '^clicked'"
  line="$(wait_window UserNotificationCenter "is the latest version" 60)"
  windows_log "$name menu answer"; shot "$name-menu-answer"
  check "[$name] the app answers \"PlantGPT $EXPECT is the latest version.\"" "$(echo "$line" | cut -f3)" \
    sh -c "printf '%s' \"\$1\" | grep -q -F 'PlantGPT $EXPECT is the latest version.'" _ "$line"
  [ -n "$line" ] && ui click UserNotificationCenter "is the latest version" OK > /dev/null
  check "[$name] the app runs on (pid $new) and reports $EXPECT on disk" "$(plist "$APP" CFBundleShortVersionString)" \
    sh -c "kill -0 $new && test '$(plist "$APP" CFBundleShortVersionString)' = '$EXPECT'"
  echo "[$name] took $(( $(date +%s) - t0 )) s"
  quit_app
}

run_variant restart Restart
section "Second install of $FROM_TAG for the \"Later\" answer"
install_n || { note "the second install failed: the run stops here"; finish; }
run_variant later Later

# ------------------------------------------------------------------------------------------------
section "After the update: identity, Gatekeeper, TCC"
{ codesign -dvvv "$APP" 2>&1; codesign -d -r- "$APP" 2>&1; } > "$OUT/codesign-after.txt"
check "the designated requirement is unchanged" "$(dr "$APP")" test "$(dr "$APP")" = "$DR_BEFORE"
GK_AFTER="$(spctl -a -t exec -vv "$APP" 2>&1)"; echo "$GK_AFTER" > "$OUT/spctl-after.txt"
check "Gatekeeper accepts the app: Notarized Developer ID" "$(echo "$GK_AFTER" | tr '\n' ' ')" \
  sh -c "printf '%s\n' \"\$1\" | grep -q ': accepted' && printf '%s\n' \"\$1\" | grep -q -x 'source=Notarized Developer ID'" _ "$GK_AFTER"
check "the app's signature is intact and stapled" "" sh -c "codesign --verify --deep --strict '$APP' && xcrun stapler validate '$APP'"
tcc_check "after"
note "A runner cannot show a TCC consent prompt. tccd allows a grant when the app satisfies the csreq stored with it, which the checks above test for each of the four grants: an app that passes needs no new prompt."

section "Where the update came from"
sudo kill -INT "$TCPDUMP" 2>/dev/null; sleep 2; TCPDUMP=""
tcpdump -r "$OUT/net.pcapng" -n -kNP -A 2>"$OUT/tcpdump-read.log" | python3 -I "$ROOT/tests/updater/net-report.py" > "$OUT/net-report.txt"
cat "$OUT/net-report.txt"
check "the app (process plantgpt) asked publikhq.com (the live feed)" "$(grep -c ' plantgpt .* publikhq\.com' "$OUT/net-report.txt") connection(s)" \
  grep -q ' plantgpt .* publikhq\.com' "$OUT/net-report.txt"
ls -la "$HOME/Downloads" > "$OUT/downloads-after.txt"
check "no file came to ~/Downloads after the $FROM_TAG dmg" "$(find "$HOME/Downloads" -type f -newer "$DMG" | tr '\n' ' ')" \
  test -z "$(find "$HOME/Downloads" -type f -newer "$DMG")"
if [ "$UPDATE" = 1 ]; then
  check "the app (process plantgpt) fetched the update from GitHub" "" \
    grep -q -E ' plantgpt .* (github\.com|release-assets\.githubusercontent\.com|objects\.githubusercontent\.com)' "$OUT/net-report.txt"
  check "no other process fetched a GitHub release asset while the app ran" "" \
    sh -c "! grep -v ' plantgpt ' '$OUT/net-report.txt' | grep -q -E '(^| |,)(github\.com|release-assets\.githubusercontent\.com|objects\.githubusercontent\.com)(,|$)'"
  # After the proof (the capture is stopped): the installed app is the published bundle, byte for byte.
  mkdir -p "$WORK/n1"
  gh release download "v$EXPECT" -R "$REPO" -p "*.app.tar.gz" -D "$WORK/n1" && tar -xzf "$WORK"/n1/*.app.tar.gz -C "$WORK/n1"
  check "the installed app is the v$EXPECT update bundle (cdhash)" "$(cdhash "$APP")" test "$(cdhash "$APP")" = "$(cdhash "$WORK/n1/PlantGPT.app")"
else
  check "the app fetched nothing from GitHub (no update)" "" sh -c "! grep -q -E ' plantgpt .*(github\.com|githubusercontent\.com)' '$OUT/net-report.txt'"
fi

curl -fsSL "$FEED" -o "$OUT/feed-after.json" || true
finish
