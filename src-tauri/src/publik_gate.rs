//! Sign in with publik: the gate's screens for the Tauri shell.
//!
//! The main window starts hidden (`visible: false` in tauri.conf.json). The gate runs on its
//! own thread from the setup hook, draws each screen of `publik::ensure_signed_in` as a native
//! message dialog, and shows the main window only after the person is signed in. There is no
//! other way past it. `PUBLIK_SELF_TEST=1` makes the module print its one line and exit instead.

use crate::publik::{self, GateUi, Screen};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tauri::{AppHandle, Manager};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};
use tauri_plugin_opener::OpenerExt;

/// One native message dialog per screen: `screen.title`, `screen.body` and `screen.note`, with
/// one button for each of `screen.buttons`. The dialog plugin runs it on the main thread and
/// blocks only this thread.
struct DialogUi {
    app: AppHandle,
}

impl GateUi for DialogUi {
    fn show(&mut self, s: &Screen, done: Arc<AtomicBool>) -> Option<&'static str> {
        let buttons = match s.buttons.as_slice() {
            [(_, a), (_, b)] => MessageDialogButtons::OkCancelCustom(a.to_string(), b.to_string()),
            [(_, a)] => MessageDialogButtons::OkCustom(a.to_string()),
            _ => MessageDialogButtons::Ok,
        };
        let detail = match s.note {
            Some(note) => format!("{}\n\n{note}", s.body),
            None => s.body.clone(),
        };
        let first = self
            .app
            .dialog()
            .message(detail)
            .title(s.title)
            .kind(MessageDialogKind::Info)
            .buttons(buttons)
            .blocking_show();
        // The poll saw the sign-in while the dialog was open: the press only
        // closed it, so the gate reads the wallet again instead of opening the browser twice.
        if done.load(Ordering::SeqCst) {
            return None;
        }
        match (first, s.buttons.as_slice()) {
            (true, [(id, _), ..]) => Some(*id),
            (false, [_, (id, _)]) => Some(*id),
            // A one-button screen closed another way (Escape): the gate shows it again.
            _ => None,
        }
    }

    fn open_url(&mut self, url: &str) {
        if let Err(e) = self.app.opener().open_url(url, None::<&str>) {
            eprintln!("publik: could not open the browser: {e}");
        }
    }
}

/// Called first in the setup hook. Runs the gate on a thread, then shows the main window.
pub fn run(app: AppHandle) {
    let spawned = std::thread::Builder::new()
        .name("publik-gate".into())
        .spawn({
            let app = app.clone();
            move || {
                let mut ui = DialogUi { app: app.clone() };
                let _gate = publik::ensure_signed_in(&mut ui);
                show_main(&app);
            }
        });
    if let Err(e) = spawned {
        // No thread, no gate: the app must still open rather than stay invisible.
        eprintln!("publik: could not start the sign-in gate: {e}");
        show_main(&app);
    }
}

fn show_main(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.set_focus();
    }
}

#[cfg(test)]
mod tests {
    //! The gate's start-up path (`publik::ensure_signed_in`) against a fake publik on 127.0.0.1
    //! (PUBLIK_ORIGIN), with a temporary home folder: no real credential is read or written,
    //! no request reaches publikhq.com, and nothing is counted (DO_NOT_TRACK=1). A fake GateUi
    //! records each screen the gate shows and presses its first button.
    use crate::publik::{self, GateUi, Screen};
    use serde_json::{json, Value};
    use std::io::{BufRead, BufReader, Read, Write};
    use std::net::TcpListener;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;

    const KEY: &str = "pk_gate_test";

    /// A fake publik. GET /api/v1/wallet answers "claimed" once `claimed` is set, and always
    /// with no plan and no balance. Returns its origin.
    fn fake_publik(claimed: Arc<AtomicBool>) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind 127.0.0.1");
        let origin = format!("http://{}", listener.local_addr().unwrap());
        let me = origin.clone();
        std::thread::spawn(move || {
            for conn in listener.incoming() {
                let Ok(mut conn) = conn else { continue };
                let Ok(read_half) = conn.try_clone() else {
                    continue;
                };
                let mut reader = BufReader::new(read_half);
                let mut request = String::new();
                if reader.read_line(&mut request).unwrap_or(0) == 0 {
                    continue;
                }
                let mut length = 0usize;
                loop {
                    let mut line = String::new();
                    if reader.read_line(&mut line).unwrap_or(0) == 0 || line.trim().is_empty() {
                        break;
                    }
                    if let Some((name, value)) = line.split_once(':') {
                        if name.trim().eq_ignore_ascii_case("content-length") {
                            length = value.trim().parse().unwrap_or(0);
                        }
                    }
                }
                let mut body = vec![0u8; length];
                let _ = reader.read_exact(&mut body);
                let path = request.split_whitespace().nth(1).unwrap_or("").to_string();
                let (status, reply) = if path == "/api/v1/wallet" {
                    let state = if claimed.load(Ordering::SeqCst) {
                        "claimed"
                    } else {
                        "anonymous"
                    };
                    (
                        200,
                        json!({
                            "claim_state": state,
                            "claim_url": format!("{me}/claim/gate-test"),
                            "account": { "handle": "gate-test" },
                            "plan": { "kind": "none", "label": null },
                            "balance_micros": 0,
                            "top_up_url": format!("{me}/wallet"),
                        }),
                    )
                } else {
                    (
                        404,
                        json!({ "error": { "type": "not_found", "message": "Not in this test." } }),
                    )
                };
                let text = reply.to_string();
                let _ = write!(
                    conn,
                    "HTTP/1.1 {status} OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{text}",
                    text.len()
                );
                let _ = conn.flush();
            }
        });
        origin
    }

    /// Records the screens; presses the first button of each. Its browser signs the person in.
    struct FakeUi {
        shown: Vec<&'static str>,
        opened: Vec<String>,
        claimed: Arc<AtomicBool>,
    }

    impl GateUi for FakeUi {
        fn show(&mut self, screen: &Screen, _done: Arc<AtomicBool>) -> Option<&'static str> {
            self.shown.push(screen.id);
            assert!(
                self.shown.len() <= 3,
                "the gate showed too many screens: {:?}",
                self.shown
            );
            screen.buttons.first().map(|(id, _)| *id)
        }

        fn open_url(&mut self, url: &str) {
            self.opened.push(url.to_string());
            self.claimed.store(true, Ordering::SeqCst);
        }
    }

    fn store_credential(choice: Option<&str>) {
        let path = publik::credential_path();
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        let mut c = json!({ "key": KEY, "install_id": "00000000-0000-4000-8000-000000000000" });
        if let Some(choice) = choice {
            c["choice"] = json!(choice);
        }
        std::fs::write(&path, c.to_string()).unwrap();
    }

    fn stored_choice() -> Value {
        publik::read_credential().expect("the credential is still there")["choice"].clone()
    }

    fn run_gate(claimed: &Arc<AtomicBool>) -> (FakeUi, Option<String>) {
        let mut ui = FakeUi {
            shown: Vec::new(),
            opened: Vec::new(),
            claimed: claimed.clone(),
        };
        let (key, _wallet, choice) = publik::ensure_signed_in(&mut ui);
        assert_eq!(key, KEY);
        (ui, choice)
    }

    /// One test, so the environment (HOME, PUBLIK_ORIGIN) is set once and no other test races it.
    #[test]
    fn sign_in_then_straight_in_with_no_pay_screen() {
        let home =
            std::env::temp_dir().join(format!("plantgpt-gate-test-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&home).unwrap();
        let claimed = Arc::new(AtomicBool::new(false));
        let origin = fake_publik(claimed.clone());
        std::env::set_var("HOME", &home);
        std::env::set_var("XDG_CONFIG_HOME", home.join(".config"));
        std::env::set_var("PUBLIK_ORIGIN", &origin);
        std::env::set_var("DO_NOT_TRACK", "1");
        std::env::remove_var("PUBLIK_API_KEY");
        std::env::remove_var("PUBLIK_SELF_TEST");

        // 1. Not signed in, no choice stored: the sign-in screen, the browser, then straight in.
        store_credential(None);
        let (ui, choice) = run_gate(&claimed);
        assert_eq!(ui.shown, ["sign_in"], "only the sign-in screen");
        assert_eq!(ui.opened, [format!("{origin}/claim/gate-test")]);
        assert_eq!(choice.as_deref(), Some("publik"));
        assert_eq!(stored_choice(), "publik");

        // 2. Signed in with no plan and no balance, no choice stored: no screen; publik is stored.
        store_credential(None);
        let (ui, choice) = run_gate(&claimed);
        assert!(ui.shown.is_empty(), "no screen at start: {:?}", ui.shown);
        assert!(ui.opened.is_empty(), "no browser at start: {:?}", ui.opened);
        assert_eq!(choice.as_deref(), Some("publik"));
        assert_eq!(stored_choice(), "publik");

        // 3. A stored choice is kept as it is (own_key from Settings, and publik).
        for kept in ["own_key", "publik"] {
            store_credential(Some(kept));
            let (ui, choice) = run_gate(&claimed);
            assert!(ui.shown.is_empty(), "no screen at start: {:?}", ui.shown);
            assert_eq!(choice.as_deref(), Some(kept));
            assert_eq!(stored_choice(), kept);
        }

        let _ = std::fs::remove_dir_all(&home);
    }
}
