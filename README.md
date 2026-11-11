# PlantGPT

![PlantGPT](docs/img/hero.png)

Pixel-parity desktop clone of [ecogpt.com](https://ecogpt.com) ("Regenerative AI") built with
Tauri v2 + React + Vite. The app opens with **Sign in with publik**. Replies come from your
publik plan (the publik API), or from [Ollama](https://ollama.com) on your own machine at no
cost. No ads. The app counts usage and sends nothing about your chats
(see [Sign in with publik](#sign-in-with-publik)).

## Install

1. Download the latest `PlantGPT_x.y.z_aarch64.dmg` from
   [Releases](https://github.com/Blueturboguy07/plantgpt/releases/latest), open it, and drag
   **PlantGPT** into Applications. The app is Developer ID–signed and notarized by Apple.
2. Install [Ollama](https://ollama.com) and start it:
   `brew install ollama && brew services start ollama`
3. Pull a chat model: `ollama pull qwen2.5:3b` (or `qwen2.5:7b` if you have ≥16 GB RAM).
4. Open PlantGPT and click **Sign in with publik**. Then choose **Get a plan** / **Connect your
   plan** (replies through the publik API) or **Use my own key** (Ollama at `localhost:11434`,
   no key needed). Settings can change the choice.

## What's cloned (and what's upgraded)

| Area | Parity | Notes |
| --- | --- | --- |
| Sidebar, empty state, input pill, tools menu | ✅ pixel-matched | tokens extracted from the real site (`UI-SPEC.md`) |
| Chat thread (user bubbles / plain assistant text, action row) | ✅ | |
| Impact drawer (isometric field, trees/CO2/H2O/light, badges, About/Friends/Rankings) | ✅ | stats computed locally, 1 tree per 100 messages |
| Search chats modal (⌘K), chat history, rename/delete | ✅ | |
| Projects | ✅ upgraded | real site gates them behind login; here they work locally |
| Markdown rendering | ⬆️ **better than the original** | real headings, numbered lists, green blockquotes, code blocks with language header + copy + syntax highlighting, KaTeX math, rounded tables |
| Web search | ⬆️ free + local | DuckDuckGo HTML results fetched natively and fed as context |
| Study mode | ⬆️ unlocked | tutoring system prompt (login-gated upstream) |
| Login/ads/third-party analytics | ❌ intentionally dropped | replaced by a Settings modal (model, theme, username) |

## Sign in with publik

Since 0.1.2 PlantGPT opens with Sign in with publik (the publik module in
`src-tauri/src/publik.rs`). The button opens the sign-in page in your browser, and the app
continues when you are signed in. After the sign-in the app sends two events to publik with
your install key: `app_opened` (one time for each launch) and `active_session` (every 30
minutes while the app runs). Each event holds the app name, the app version, the operating
system, the CPU type and a random install ID, so you count once across your devices. No chats,
no prompts, no file names and no user name are sent. To turn counting off, set
`DO_NOT_TRACK=1` in the environment, or put `{"usage": false}` in
`~/Library/Application Support/publik/consent.json`. Details: https://publikhq.com/skills/telemetry.md

With **Connect your plan**, replies stream through the publik API (`publik-balanced`) from the
Rust side; the install key never reaches the webview. With **Use my own key**, replies come
from Ollama as before.

A release build needs the publik app token of this listing: `PUBLIK_APP_TOKEN` at build time,
or `src-tauri/publik-app-token.txt` (public by design). A build with neither says "This build
has no publik app token."

## Develop

```sh
npm install
npm run tauri dev
```

## Build

```sh
npm run tauri build
# → src-tauri/target/release/bundle/macos/PlantGPT.app (+ .dmg)
# A release: scripts/build-macos.sh, with PUBLIK_APP_TOKEN set or src-tauri/publik-app-token.txt filled.
```

## Keyboard

- `⌘K` — search chats
- `⌘J` — new chat
- `Enter` send · `Shift+Enter` newline
