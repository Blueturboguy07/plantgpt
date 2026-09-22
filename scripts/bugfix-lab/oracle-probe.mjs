// bugfix-lab oracle probe for cluster: plantgpt-windows-macos-brew-hint-shown-on-windows
//
// Behavioural check (not a source grep): builds the real web bundle (dist/), serves it,
// loads it in a real Chromium instance, forces the Ollama health probe
// (http://localhost:11434/api/tags) to fail the way it does when Ollama isn't running,
// and reads the ACTUAL RENDERED setup-banner text the user sees — the same banner the
// reporter's screenshot shows: "Ollama isn't running. Run brew services start ollama".
//
// PRESENT (exit 1): the rendered banner names a macOS-only remedy (`brew`) regardless
//   of the OS this browser/runner reports itself as.
// ABSENT  (exit 0): the rendered banner is OS-appropriate (no `brew` on a non-mac
//   platform.navigator, or the app now checks the platform before choosing the remedy).
import { chromium } from "playwright";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join } from "node:path";

const DIST = join(process.cwd(), "dist");
const MIME = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json" };

const server = createServer(async (req, res) => {
  let p = req.url.split("?")[0];
  if (p === "/") p = "/index.html";
  try {
    const data = await readFile(join(DIST, p));
    res.writeHead(200, { "Content-Type": MIME[extname(p)] || "application/octet-stream" });
    res.end(data);
  } catch {
    res.writeHead(404);
    res.end();
  }
});

await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;

const browser = await chromium.launch();
const page = await browser.newPage();
page.on("console", (m) => console.log("[page]", m.text()));

// Force the localhost:11434 health probe to fail — this is the reporter's actual
// state ("even thou[gh] the ollama is running the plantgpt still not working"):
// whatever the real cause, the app's own health check reports Ollama unreachable,
// which is exactly the condition that produces the setup-banner in the screenshot.
await page.route("http://localhost:11434/**", (route) => route.abort("connectionrefused"));

await page.goto(`http://127.0.0.1:${port}/`);
// ollamaHealth() uses AbortSignal.timeout(2500); give it margin.
await page.waitForSelector(".setup-banner", { timeout: 8000 }).catch(() => {});

const bannerText = await page.locator(".setup-banner").innerText().catch(() => null);
const platform = await page.evaluate(() => navigator.platform || navigator.userAgentData?.platform || "unknown");

console.log("RUNNER_REPORTED_PLATFORM:", platform);
console.log("BANNER_TEXT:", JSON.stringify(bannerText));

await browser.close();
server.close();

if (bannerText && /\bbrew\b/i.test(bannerText)) {
  console.log("BUGFIX_LAB_PRESENT");
  process.exit(1);
} else if (bannerText) {
  console.log("BUGFIX_LAB_ABSENT");
  process.exit(0);
} else {
  console.log("BUGFIX_LAB_COULD_NOT_OBSERVE (no .setup-banner rendered at all)");
  process.exit(2);
}
