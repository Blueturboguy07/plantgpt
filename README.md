# PlantGPT

Pixel-parity desktop clone of [ecogpt.com](https://ecogpt.com) ("Regenerative AI") built with
Tauri v2 + React + Vite — except it's **100% local and free**: inference runs through
[Ollama](https://ollama.com) on your own machine. No accounts, no keys, no cloud, no ads,
no analytics, no cost.

## Install

1. Download the latest `PlantGPT_x.y.z_aarch64.dmg` from
   [Releases](https://github.com/Blueturboguy07/plantgpt/releases/latest), open it, and drag
   **PlantGPT** into Applications. The app is Developer ID–signed and notarized by Apple.
2. Install [Ollama](https://ollama.com) and start it:
   `brew install ollama && brew services start ollama`
3. Pull a chat model: `ollama pull qwen2.5:3b` (or `qwen2.5:7b` if you have ≥16 GB RAM).
4. Open PlantGPT — it finds Ollama at `localhost:11434` automatically.

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
| Login/ads/analytics | ❌ intentionally dropped | replaced by a Settings modal (model, theme, username) |

## Develop

```sh
npm install
npm run tauri dev
```

## Build

```sh
npm run tauri build
# → src-tauri/target/release/bundle/macos/PlantGPT.app (+ .dmg)
```

## Keyboard

- `⌘K` — search chats
- `⌘J` — new chat
- `Enter` send · `Shift+Enter` newline
