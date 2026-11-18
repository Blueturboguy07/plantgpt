#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod publik;
mod publik_chat;
mod publik_gate;
mod updates;

/// The menu item that runs `updates::check_now` (macOS app menu).
#[cfg(target_os = "macos")]
const CHECK_FOR_UPDATES: &str = "check-for-updates";

fn main() {
    // Updater test hook (PUBLIK_UPDATE_SELF_TEST): no window, no gate; see updates.rs.
    let update_self_test = updates::self_test_mode();

    let builder = updates::plugins(tauri::Builder::default());
    #[cfg(target_os = "macos")]
    let builder = builder.menu(app_menu).on_menu_event(|app, event| {
        if event.id() == CHECK_FOR_UPDATES {
            updates::check_now(app);
        }
    });

    builder
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .manage(publik_chat::Chats::default())
        .setup(move |app| {
            if let Some(mode) = update_self_test {
                updates::run_self_test(app.handle(), mode);
                return Ok(());
            }
            // Update checks start at launch, before the gate, so a gate bug can be fixed by an
            // update: 10 s after launch, then once a day (updates.rs).
            updates::start(app.handle());
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

/// macOS: the default menu Tauri gives the app, with "Check for Updates…" after
/// "About PlantGPT" in the app menu. Nothing else in the menu changes.
#[cfg(target_os = "macos")]
fn app_menu(app: &tauri::AppHandle) -> tauri::Result<tauri::menu::Menu<tauri::Wry>> {
    use tauri::menu::{Menu, MenuItem, MenuItemKind};
    let menu = Menu::default(app)?;
    if let Some(MenuItemKind::Submenu(app_menu)) = menu.items()?.into_iter().next() {
        let item = MenuItem::with_id(app, CHECK_FOR_UPDATES, "Check for Updates…", true, None::<&str>)?;
        app_menu.insert(&item, 1)?;
    }
    Ok(menu)
}
