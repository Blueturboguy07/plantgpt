"""publik-telemetry-smoke.py <main executable> <expected version> <slug> [out json]

Starts the app 2 times for a few seconds with a temporary home folder. The usage counts go to a listener on
127.0.0.1 (a random port), never to publikhq.com.
  Run 1: one correct "app_opened" request must arrive and the app must stay up.
  Run 2: with DO_NOT_TRACK=1 no request must arrive and no telemetry.json must be made.
Standard library only. Exit code 0 only when both runs pass.
"""
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

exe, want_version, slug = sys.argv[1:4]
out_path = sys.argv[4] if len(sys.argv) > 4 else None
UUID4 = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
ALLOWED = {"v", "app", "install_id", "event", "app_version", "os", "arch"}


def listener():
    requests = []

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def _handle(self):
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length).decode("utf-8", "replace") if length else ""
            requests.append({"method": self.command, "path": self.path, "headers": {k.lower(): v for k, v in self.headers.items()}, "body": body})
            self.send_response(204)
            self.send_header("Content-Length", "0")
            self.send_header("Connection", "close")
            self.end_headers()

        do_POST = do_GET = do_PUT = do_OPTIONS = do_HEAD = _handle

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True).start()
    return server, requests


def run(mode, seconds):
    server, requests = listener()
    home = tempfile.mkdtemp(prefix="plantgpt-smoke-home-")
    env = {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": home,
        "CFFIXED_USER_HOME": home,  # WebKit keeps its data here too, not in the real home
        "USER": os.environ.get("USER", ""),
        "LANG": "en_US.UTF-8",
        "PUBLIK_TELEMETRY_URL": "http://127.0.0.1:%d/api/v1/telemetry" % server.server_address[1],
        "PUBLIK_TELEMETRY_DEBUG": "1",
    }
    if mode == "dnt":
        env["DO_NOT_TRACK"] = "1"
    started = time.time()
    proc = subprocess.Popen([exe], env=env, cwd=home, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    while time.time() - started < seconds and proc.poll() is None:
        time.sleep(0.25)
        if mode == "track" and requests and time.time() - started >= 8:
            break
    up = proc.poll() is None
    ran_for = round(time.time() - started, 1)
    if up:
        proc.send_signal(signal.SIGTERM)
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
    output = (proc.stdout.read() or b"").decode("utf-8", "replace")
    time.sleep(0.3)
    server.shutdown()
    server.server_close()
    id_file = os.path.join(home, "Library", "Application Support", "publik", "telemetry.json")
    result = {
        "mode": mode,
        "stayed_up": up,
        "ran_seconds": ran_for,
        "exit_code_before_quit": None if up else proc.returncode,
        "requests": list(requests),
        "debug_lines": [line for line in output.splitlines() if "publik-telemetry" in line],
        "telemetry_json_made": os.path.exists(id_file),
        "temp_home": True,
    }
    subprocess.run(["/bin/rm", "-rf", home], check=False)
    return result


def check_track(result):
    faults = []
    if not result["stayed_up"]:
        faults.append("the app did not stay up")
    posts = [r for r in result["requests"] if r["method"] == "POST" and r["path"] == "/api/v1/telemetry"]
    if len(result["requests"]) != 1 or len(posts) != 1:
        faults.append("want exactly 1 POST /api/v1/telemetry, got %d requests" % len(result["requests"]))
        return faults
    request = posts[0]
    try:
        body = json.loads(request["body"])
    except ValueError:
        return faults + ["the body is not JSON"]
    want = {"v": 1, "app": slug, "event": "app_opened", "app_version": want_version, "os": "macos"}
    for name, value in want.items():
        if body.get(name) != value:
            faults.append("%s is %r, want %r" % (name, body.get(name), value))
    if not UUID4.match(str(body.get("install_id", ""))):
        faults.append("install_id is not a lowercase UUID v4")
    if body.get("arch") not in ("arm64", "x64"):
        faults.append("arch is %r" % body.get("arch"))
    if set(body) - ALLOWED:
        faults.append("extra fields: %s" % sorted(set(body) - ALLOWED))
    if "origin" in request["headers"]:
        faults.append("the request has an Origin header")
    if "authorization" in request["headers"]:
        faults.append("the request has an Authorization header (signed out is expected)")
    if "application/json" not in request["headers"].get("content-type", ""):
        faults.append("Content-Type is not application/json")
    if not result["telemetry_json_made"]:
        faults.append("telemetry.json was not made")
    return faults


def check_dnt(result):
    faults = []
    if not result["stayed_up"]:
        faults.append("the app did not stay up")
    if result["requests"]:
        faults.append("%d requests arrived with DO_NOT_TRACK=1" % len(result["requests"]))
    if result["telemetry_json_made"]:
        faults.append("telemetry.json was made with DO_NOT_TRACK=1")
    return faults


track = run("track", 18)
track["faults"] = check_track(track)
dnt = run("dnt", 10)
dnt["faults"] = check_dnt(dnt)
report = {"app": slug, "expected_version": want_version, "executable": exe, "track": track, "do_not_track": dnt, "pass": not track["faults"] and not dnt["faults"]}
print(json.dumps(report, indent=2))
if out_path:
    with open(out_path, "w") as handle:
        json.dump(report, handle, indent=2)
        handle.write("\n")
print("RESULT: " + ("PASS" if report["pass"] else "FAIL"))
sys.exit(0 if report["pass"] else 1)
