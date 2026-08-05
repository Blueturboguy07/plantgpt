// Free local web search: fetch DuckDuckGo's HTML results and extract the top hits.
// No API, no key, no cost. Works through the Tauri http plugin (native request).

const isTauri = () => typeof window !== "undefined" && !!window.__TAURI_INTERNALS__;

async function getFetch() {
  if (isTauri()) {
    const mod = await import("@tauri-apps/plugin-http");
    return mod.fetch;
  }
  return window.fetch.bind(window);
}

const UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)";

function unwrapDdgHref(href) {
  // ddg wraps urls: //duckduckgo.com/l/?uddg=<encoded>
  const m = (href || "").match(/uddg=([^&]+)/);
  return m ? decodeURIComponent(m[1]) : href || "";
}

async function fetchDoc(url) {
  const f = await getFetch();
  const res = await f(url, {
    method: "GET",
    headers: { "User-Agent": UA },
    signal: AbortSignal.timeout(9000),
  });
  if (!res.ok) throw new Error(`search failed (${res.status})`);
  return new DOMParser().parseFromString(await res.text(), "text/html");
}

function parseHtmlEndpoint(doc, max) {
  const results = [];
  for (const el of doc.querySelectorAll(".result")) {
    const a = el.querySelector("a.result__a");
    const snip = el.querySelector(".result__snippet");
    if (!a) continue;
    const href = unwrapDdgHref(a.getAttribute("href"));
    if (!href.startsWith("http")) continue;
    results.push({
      title: a.textContent.trim(),
      url: href,
      snippet: snip ? snip.textContent.trim() : "",
    });
    if (results.length >= max) break;
  }
  return results;
}

function parseLiteEndpoint(doc, max) {
  const results = [];
  for (const a of doc.querySelectorAll("a.result-link")) {
    const href = unwrapDdgHref(a.getAttribute("href"));
    if (!href.startsWith("http")) continue;
    // snippet lives in a following table row
    let snippet = "";
    const tr = a.closest("tr");
    let row = tr?.nextElementSibling;
    for (let i = 0; i < 2 && row; i++, row = row.nextElementSibling) {
      const td = row.querySelector(".result-snippet");
      if (td) { snippet = td.textContent.trim(); break; }
    }
    results.push({ title: a.textContent.trim(), url: href, snippet });
    if (results.length >= max) break;
  }
  return results;
}

export async function webSearch(query, max = 5) {
  const q = encodeURIComponent(query);
  // Primary endpoint; falls back to DDG Lite when throttled (anomaly page has no results).
  try {
    const doc = await fetchDoc(`https://html.duckduckgo.com/html/?q=${q}`);
    const results = parseHtmlEndpoint(doc, max);
    if (results.length) return results;
  } catch { /* fall through to lite */ }
  const doc = await fetchDoc(`https://lite.duckduckgo.com/lite/?q=${q}`);
  return parseLiteEndpoint(doc, max);
}

// Fetch a result page and pull out its readable text.
async function readPageText(url) {
  const f = await getFetch();
  const res = await f(url, {
    method: "GET",
    headers: { "User-Agent": UA, "Accept": "text/html" },
    signal: AbortSignal.timeout(8000),
  });
  if (!res.ok) throw new Error(`page fetch failed (${res.status})`);
  const type = res.headers.get("content-type") || "";
  if (type && !type.includes("html")) throw new Error("not html");
  const doc = new DOMParser().parseFromString(await res.text(), "text/html");
  for (const sel of ["script", "style", "noscript", "svg", "nav", "header", "footer", "aside", "form", "iframe"]) {
    doc.querySelectorAll(sel).forEach((el) => el.remove());
  }
  const root =
    doc.querySelector("article") ||
    doc.querySelector("main") ||
    doc.querySelector('[role="main"]') ||
    doc.body;
  const text = (root?.textContent || "").replace(/\s+/g, " ").trim();
  return text.slice(0, 3000);
}

// Read the top N result pages in parallel; keep the ones with real content.
export async function readTopPages(results, n = 2) {
  const targets = results.slice(0, n);
  const settled = await Promise.allSettled(targets.map((r) => readPageText(r.url)));
  const pages = [];
  settled.forEach((s, i) => {
    if (s.status === "fulfilled" && s.value.length > 200) {
      pages.push({ title: targets[i].title, url: targets[i].url, text: s.value });
    }
  });
  return pages;
}

export function pagesContextMessage(pages) {
  return (
    "Full-text excerpts from the top search results (fetched just now):\n\n" +
    pages
      .map((p) => `=== ${p.title}\n${p.url}\n${p.text}`)
      .join("\n\n") +
    "\n\nGround your answer in these excerpts where relevant, citing the source as a markdown link."
  );
}

export function searchContextMessage(query, results) {
  const lines = results.map(
    (r, i) => `[${i + 1}] ${r.title}\n${r.url}\n${r.snippet}`
  );
  return (
    `Web search results for "${query}" (retrieved just now):\n\n` +
    lines.join("\n\n") +
    "\n\nUse these results to answer the user's message. Cite sources inline as markdown links when you rely on them."
  );
}
