// bugfix-lab probe for plantgpt-20261021-1652b7: desktop app says "Ollama isn't running"
// while a real Ollama is serving http://localhost:11434.
// Drives the REAL built PlantGPT.exe (WebView2) over CDP and reads the rendered setup banner.
//   banner contains "isn't running"  -> exit 1 (PRESENT)
//   banner absent or "No local models" -> exit 0 (ABSENT: the app detected Ollama)
//   cannot attach / app never rendered -> exit 2
import { chromium } from "playwright-core";

const CDP = "http://127.0.0.1:9222";
let browser;
for (let i = 0; i < 15 && !browser; i++) {
  try { browser = await chromium.connectOverCDP(CDP); } catch { await new Promise((r) => setTimeout(r, 1000)); }
}
if (!browser) { console.log("BUGFIX_LAB_COULD_NOT_OBSERVE (CDP attach failed)"); process.exit(2); }

let page;
for (let i = 0; i < 30 && !page; i++) {
  page = browser.contexts().flatMap((c) => c.pages()).find((p) => !p.url().startsWith("devtools"));
  if (!page) await new Promise((r) => setTimeout(r, 1000));
}
if (!page) { console.log("BUGFIX_LAB_COULD_NOT_OBSERVE (no page)"); process.exit(2); }
console.log("PAGE_URL:", page.url());
console.log("USER_AGENT:", await page.evaluate(() => navigator.userAgent));
console.log("IS_TAURI:", await page.evaluate(() => !!window.__TAURI_INTERNALS__));

await page.waitForSelector("textarea, [contenteditable], .composer", { timeout: 30000 }).catch(() => {});
// ollamaHealth() has a 2.5s timeout and runs once at mount; give it margin.
await new Promise((r) => setTimeout(r, 6000));

const banner = await page.locator(".setup-banner").innerText().catch(() => null);
console.log("BANNER_TEXT:", JSON.stringify(banner));
const ok = await page.evaluate(() => !!document.querySelector("#root")?.children.length);
if (!ok) { console.log("BUGFIX_LAB_COULD_NOT_OBSERVE (app did not render)"); process.exit(2); }

await browser.close().catch(() => {});
if (banner && /isn't running/i.test(banner)) { console.log("BUGFIX_LAB_PRESENT"); process.exit(1); }
console.log("BUGFIX_LAB_ABSENT");
process.exit(0);
