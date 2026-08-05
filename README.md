# PlantGPT (EcoGPT desktop clone)

Pixel-parity desktop clone of [ecogpt.com](https://ecogpt.com) ("Regenerative AI") built with
Tauri v2 + React + Vite — except it's **100% local and free**: inference runs through
[Ollama](https://ollama.com) on your own machine. No accounts, no keys, no cloud, no ads,
no analytics, no cost.

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

## Requirements

- macOS with [Ollama](https://ollama.com): `brew install ollama && brew services start ollama`
- At least one chat model: `ollama pull qwen2.5:3b` (or `qwen2.5:7b`, etc.)

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
