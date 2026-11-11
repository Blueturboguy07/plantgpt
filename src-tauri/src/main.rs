#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod publik;
mod publik_chat;
mod publik_gate;

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .manage(publik_chat::Chats::default())
        .setup(|app| {
            // Sign in with publik, before the main window is shown: the window in
            // tauri.conf.json starts hidden, and the gate thread shows it once the
            // person is signed in. Usage counting (app_opened, active_session)
            // starts there too, with the install key.
            publik_gate::run(app.handle().clone());
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            publik_chat::publik_provider,
            publik_chat::publik_set_choice,
            publik_chat::publik_chat,
            publik_chat::publik_chat_stop,
        ])
        .run(tauri::generate_context!())
        .expect("error while running PlantGPT");
}
