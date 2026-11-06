#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod publik_telemetry;

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            // Anonymous usage counts (publik telemetry v1). Runs on its own thread.
            publik_telemetry::start("plantgpt", &app.package_info().version.to_string(), None);
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running PlantGPT");
}
