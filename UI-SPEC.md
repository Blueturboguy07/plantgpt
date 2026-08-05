# EcoGPT UI spec — extracted from ecogpt.com on 2026-08-04

Live exploration of https://ecogpt.com (logged-out web app). All values are computed styles
from the real DOM at 1037×801 CSS px viewport, dark theme (html.dark).

## Identity / product facts
- "EcoGPT — Regenerative AI", ECOGPT INC (NYC public-benefit co).
- Chat backend: POST https://ecogptbackend.vercel.app/api/chat8-free (Vercel; models served on Groq LPUs).
- Persona claim (from its own reply): "efficient open-source mixture-of-experts models…
  ~10x fewer active parameters than the big providers, hosted on renewable energy in Finland…
  I can search the live web, handle long documents… Every interaction helps plant real trees —
  over 81,000 planted so far."
- 100 messages = 1 tree (App Store copy). Ads injected under replies (Gravity network + "AD" tag).
- Analytics: GA + Mixpanel. KaTeX fonts loaded → math rendering supported.

## Fonts
- Body/UI: "SF Pro Display","SF Pro Text",-apple-system,system-ui,"Segoe UI",Roboto
- --font-display: Bricolage Grotesque (loaded 400–800; marketing/display use)
- --font-serif: Instrument Serif; --font-signature: "Shadows Into Light" (About drawer signature)
- Code: Inconsolata, Monaco, Consolas, monospace @14px

## Design tokens (dark)
primary #4ead62 · primary-dark #3d9150 · primary-light #60c474 · accent #4a5568
bg #212121 · bg-alt/sidebar #171717 · bg-secondary #2f2f2f · bg-tertiary #3a3a3a
text-primary #f5f5f5 · text-secondary #a0a0a0 · text-muted #6b7280 · preview #9ca3af
border #3a3a3a · icon-fill #9ca3af · sidebar-edge #ffffff18 · sidebar-hover #2a2a2a · sidebar-active #2f2f2f
card-bg #2f2f2f · card-border #3a3a3a · stats-card-bg #1e3326 · input-bg #2f2f2f · placeholder #6b7280
chat-input-shell: bg #2f2f2f, border transparent, shadow "0 3px 6px #0000000f, inset 0 0 1px #fff3"
send-btn: bg #fff, text #000 · avatar-teal #14b8a6 · sidebar-scrollbar-thumb #ffffff40

## Design tokens (light)
primary #2d7a3a · primary-dark #1f5c2a · primary-light #3d9148 · accent #bacc80 · accent-light #d4e4a5
bg #fff · bg-alt #f7f7f5 · bg-secondary #f2f2f2 · bg-tertiary #e8e8e8
text #333/#666/#999 · border #e5e5e0 · icon #5d5d5d · sidebar-bg #fff · sidebar-edge #00000014
hover #f2f2f2 · active #e3e3e3 · card #fff/#e5e5e5 · stats-card #f5f9f5
input-shell: bg #fff, border #0000002e, shadow 0 0 8px #00000014 · send-btn bg #000 text #fff
forest #275243/#3d7a5a/#5a9a7a · earth #8b7355/#c4a77d/#f5f0e8

## Layout metrics
- Sidebar: 260px wide, bg #171717, border-right 1px rgba(255,255,255,.094). Collapsed rail ≈60px (icons only).
- Wordmark "EcoGPT": 17px/700 #f5f5f5, top-left; panel-collapse icon button top-right of sidebar.
- Nav items: 243×36px, radius 8, font 16/400 white, icons ~18px; hover #2a2a2a.
  Items: New chat (pencil), Search chats (magnifier), Projects (folder+, login-gated on real site).
- Sidebar bottom: Discord row "Help build EcoGPT" (muted, ext-link arrow) + full-width green
  "Log in" pill button (h≈44, radius ~10, bg #6aab6e-ish gradient? computed solid green).
- Top right of content: green "Sign in" pill + 🌲 tree emoji button (~28px) that opens Impact drawer.
- Empty state: 🌍 emoji (~56px) above centered "What can I help with?" (≈28px, 400).
  Bottom-center green link "What is EcoGPT?".
- Input shell: max-w 736px, h 57 (single line), radius 28, bg #2f2f2f,
  shadow 0 3px 6px rgba(0,0,0,.06) + inset 0 0 1px rgba(255,255,255,.2); border .5px transparent.
  Textarea 17px/28px, placeholder "Ask anything..." #6b7280.
  Left: + button (36px, turns into ✕ "Tools" tooltip when menu open).
  Right: mic icon button + 36px round send (bg #fff, black ↑; disabled = gray).
- Tools menu (from +): "Add photos & files" (paperclip), "Web search" (globe), divider,
  caption "Log in to unlock more tools.", disabled: "Create image" (image icon), "Study mode" (book).
- Chat column: 777px wide. User bubble: right-aligned, bg #2f2f2f, radius 24, padding 10px 16px,
  16px text, max-w ≈80%. Assistant: plain left text 16px/26.4px #f5f5f5, no bubble.
- Action row under assistant reply: copy, thumbs-up, thumbs-down, share, regenerate (16px icons, #9ca3af).
- Footer: "EcoGPT can make mistakes. Learn more here." (link green) centered ~12px.
- Scroll-to-bottom: floating circle button (~36px, #2f2f2f, ↓) centered above composer.
- Search chats modal: ~600px wide, bg #2f2f2f, radius ~16; header row 🔍 + "Search chats..." + ✕;
  "New chat" row; empty: "No conversations yet" centered muted.
- Login modal (real): 🌍, "Welcome to EcoGPT" 24px, "Sign in to continue", Apple/Google buttons,
  or-divider, Sign in/Create account tabs, email+password, green "Sign in with email". (Clone: replaced by Settings.)

## Markdown rendering (theirs is WEAK — clone upgrades this)
- Real site: headings render as plain body text, ordered lists lose numbers, blockquotes unstyled.
- Tables: bordered grid #3a3a3a, cells 12×16px pad, 14px, header 400 transparent bg, body text #a0a0a0.
- Code: container radius ~8, Inconsolata 14px, syntax colors (VS-Code-dark-ish), pre pad 12px.
- CLONE: proper headings, numbered/nested lists, green-border blockquotes, rounded table container,
  code header bar w/ language + copy, KaTeX math, green links.

## Impact drawer (tree button, right side, ~400px wide)
- Top section: light sage bg (#e7ecd8-ish) with isometric 3D grass-tile field illustration; "<" back button.
- Overlapping dark profile card (radius ~24): 48px round avatar (letter), "@user" 18px,
  share icon; big "0 🌳 / Trees planted" + green progress bar; right stack:
  🍃 "kg of CO2 saved", 💧 "L of H2O saved", 💡(orange) "hr of light saved", each w/ tiny bar (green/blue/orange).
- Badges card: "Badges >" + 4 gray scalloped-seal badges: First Leaf, Team Player, Eco Influencer, Seed.
- Segmented tabs: About | Friends | Rankings (pill container, active chip darker).
- About tab: "About" card → "The AI Problem" (Our planet is dying because of Big AI. / Every day,
  global AI systems waste… • 100m+ gallons of water • 10x as much electricity as all of Greenland
  • 7000+ tons of CO2 emissions / EcoGPT is the world's first Regenerative AI) →
  "How does EcoGPT help?" (Efficient ai uses 10% as many resources as big ai.) + two white cards:
  big grid of 🪨/⚡/💧 emoji (10 cols × 5 rows) captioned "Big ai models" vs single column card
  "Efficient ai models" → "Our promise" (climate-positive paragraphs) + handwritten green
  "- EcoGPT Team" (Shadows Into Light) → "Policy Tracker" card (dark-green bg #1e3326, map icon,
  green title, "Follow AI, data-center, and energy policy.", ↗).
- Friends tab: "My friends" card + "+" add button, empty-state silhouettes.
- Rankings tab: "Leaderboard >" card; hexagonal avatar above "@user", "🌳 0" pill, "1st" podium block.

## Clone decisions (desktop, Tauri v2) — 100% LOCAL, ZERO COST (user directive 2026-08-04)
- Inference: Ollama at http://localhost:11434 (no keys, no cloud, no cost). NDJSON streaming
  via /api/chat; model picker populated from /api/tags. Machine has qwen2.5:7b + qwen2.5:3b.
- Requests via tauri-plugin-http in-app (native client → no CORS/origin issues), window.fetch in dev.
- Web search menu item → free local implementation: fetch https://html.duckduckgo.com/html/?q=…,
  parse top results, prepend as context. No API, no key.
- Study mode → enabled via system prompt (real site gates it behind login).
- Create image → disabled entry (no local image gen in v1).
- Login/Sign in replaced by Settings (Ollama status, model picker, theme, username). All data local.
- No ads, no analytics. Impact stats computed locally: 1 tree/100 msgs, CO2 4g·msg, H2O 0.02L·msg, light 0.027h·msg.
  (Local spin: running on your own machine — "the most regenerative AI is the one that never leaves your laptop".)
