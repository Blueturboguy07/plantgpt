//! publik API chat for the webview. The install key never leaves this process: the webview
//! sends the messages, Rust runs the request through the system curl with the key, and streams
//! the reply back as `publik-chat` events: `{id, delta}` ..., then `{id, done}`, or
//! `{id, error, top_up_url}` (a 402 shows its message plus that one link).

use crate::publik::{self, Provider};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::process::{Child, ChildStdout, Command, Stdio};
use std::sync::Mutex;
use tauri::{AppHandle, Emitter, Manager, State};

/// The curl of each reply in flight, by the id the webview chose, so Stop can end it.
#[derive(Default)]
pub struct Chats(Mutex<HashMap<String, Child>>);

/// What the webview may know about the engine: never the key.
#[tauri::command]
pub fn publik_provider() -> Value {
    match publik::resolve_provider(None) {
        Provider::Publik { .. } => json!({ "kind": "publik" }),
        Provider::Own { .. } => json!({ "kind": "own" }),
        Provider::NeedsOwnKey => json!({ "kind": "needs_own_key" }),
    }
}

/// The answer to the gate's plan screen, changed from Settings. `None` asks again at the next start.
#[tauri::command]
pub fn publik_set_choice(choice: Option<String>) -> Result<(), String> {
    match choice.as_deref() {
        None | Some("publik") | Some("own_key") => {
            publik::set_choice(choice.as_deref());
            Ok(())
        }
        Some(other) => Err(format!("unknown choice: {other}")),
    }
}

/// `POST {base_url}/chat/completions` with `stream: true`; the reply comes back as events.
#[tauri::command]
pub fn publik_chat(
    app: AppHandle,
    chats: State<'_, Chats>,
    id: String,
    body: Value,
) -> Result<(), String> {
    let Provider::Publik { base_url, api_key } = publik::resolve_provider(None) else {
        return Err("This app is not connected to a publik plan. Change it in Settings.".into());
    };
    let mut body = body;
    body["stream"] = json!(true);
    if !body["model"].is_string() {
        body["model"] = json!(publik::MODELS[1]);
    }
    // The body rides a private file, never argv; the key rides a curl config on stdin.
    let body_file =
        std::env::temp_dir().join(format!("plantgpt-publik-{}.json", uuid::Uuid::new_v4()));
    write_private(&body_file, &body.to_string())
        .map_err(|e| format!("could not write the request: {e}"))?;
    let url = format!("{base_url}/chat/completions");
    let data = format!("@{}", body_file.display());
    let spawned = Command::new("curl")
        .args([
            "-sS", "-N", "-D", "-", "-K", "-", "-m", "600", "-X", "POST", &url,
        ])
        .args([
            "-H",
            "content-type: application/json",
            "--data-binary",
            &data,
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn();
    let mut child = match spawned {
        Ok(child) => child,
        Err(e) => {
            let _ = std::fs::remove_file(&body_file);
            return Err(format!("curl: {e}"));
        }
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ =
            stdin.write_all(format!("header = \"Authorization: Bearer {api_key}\"\n").as_bytes());
    }
    let Some(stdout) = child.stdout.take() else {
        let _ = child.kill();
        let _ = std::fs::remove_file(&body_file);
        return Err("curl gave no output".into());
    };
    chats
        .0
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .insert(id.clone(), child);
    std::thread::spawn(move || {
        stream(&app, &id, stdout);
        let finished = app
            .state::<Chats>()
            .0
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(&id);
        if let Some(mut child) = finished {
            let _ = child.wait();
        }
        let _ = std::fs::remove_file(&body_file);
    });
    Ok(())
}

/// Stop: ends the curl of that reply; its stream then closes with `done`.
#[tauri::command]
pub fn publik_chat_stop(chats: State<'_, Chats>, id: String) {
    if let Some(mut child) = chats
        .0
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .remove(&id)
    {
        let _ = child.kill();
        let _ = child.wait();
    }
}

fn write_private(path: &std::path::Path, text: &str) -> std::io::Result<()> {
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options.open(path)?.write_all(text.as_bytes())
}

/// Reads curl's output: the status line and headers (`-D -`), then the SSE body.
fn stream(app: &AppHandle, id: &str, stdout: ChildStdout) {
    let emit = |payload: Value| {
        let _ = app.emit("publik-chat", payload);
    };
    let mut lines = BufReader::new(stdout).lines().map_while(Result::ok);
    // Headers: "HTTP/1.1 200 OK" (a "100 Continue" block may come first), then a blank line.
    let mut status = 0u16;
    loop {
        let Some(line) = lines.next() else {
            emit(json!({ "id": id, "error": "publik is not reachable. Check your connection." }));
            emit(json!({ "id": id, "done": true }));
            return;
        };
        if line.starts_with("HTTP/") {
            status = line
                .split_whitespace()
                .nth(1)
                .and_then(|s| s.parse().ok())
                .unwrap_or(0);
        } else if line.trim().is_empty() && status != 100 {
            break;
        }
    }
    if status != 200 {
        let text = lines.collect::<Vec<_>>().join("\n");
        let body: Value = serde_json::from_str(&text).unwrap_or(json!({}));
        let (message, top_up_url) = if status == 402 {
            publik::top_up_url_from_402(&body)
        } else {
            let message = body["error"]["message"].as_str().map(String::from);
            (
                message.unwrap_or_else(|| format!("publik API answered {status}.")),
                None,
            )
        };
        emit(json!({ "id": id, "error": message, "top_up_url": top_up_url }));
        emit(json!({ "id": id, "done": true }));
        return;
    }
    for line in lines {
        let Some(data) = line.strip_prefix("data:") else {
            continue;
        };
        let data = data.trim();
        if data == "[DONE]" {
            break;
        }
        let Ok(v) = serde_json::from_str::<Value>(data) else {
            continue;
        };
        if let Some(message) = v["error"]["message"].as_str() {
            emit(json!({ "id": id, "error": message, "top_up_url": v["error"]["top_up_url"] }));
            break;
        }
        if let Some(delta) = v["choices"][0]["delta"]["content"].as_str() {
            if !delta.is_empty() {
                emit(json!({ "id": id, "delta": delta }));
            }
        }
    }
    emit(json!({ "id": id, "done": true }));
}
