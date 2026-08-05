// Local inference via Ollama — no keys, no cloud, no cost.
// Inside Tauri we use the native http plugin (no CORS/origin restrictions);
// in the browser (vite dev) we fall back to window.fetch, which Ollama's
// default localhost origins allow.

const BASE = "http://localhost:11434";

const isTauri = () => typeof window !== "undefined" && !!window.__TAURI_INTERNALS__;

async function getFetch() {
  if (isTauri()) {
    const mod = await import("@tauri-apps/plugin-http");
    return mod.fetch;
  }
  return window.fetch.bind(window);
}

export async function ollamaHealth() {
  try {
    const f = await getFetch();
    const res = await f(`${BASE}/api/tags`, { signal: AbortSignal.timeout(2500) });
    if (!res.ok) return { running: false, models: [] };
    const data = await res.json();
    const models = (data.models || [])
      .map((m) => m.name)
      .filter((n) => !n.includes("embed"));
    return { running: true, models };
  } catch {
    return { running: false, models: [] };
  }
}

// Streams { content } chunks. messages: [{role, content, images?}]
export async function* streamChat({ model, messages, signal }) {
  const f = await getFetch();
  const res = await f(`${BASE}/api/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    // 16k context so grounding excerpts + history fit (Ollama's default 4k truncates).
    body: JSON.stringify({ model, messages, stream: true, options: { num_ctx: 16384 } }),
    signal,
  });
  if (!res.ok) {
    let msg = `Ollama error (${res.status})`;
    try {
      const e = await res.json();
      if (e.error) msg = e.error;
    } catch { /* ignore */ }
    throw new Error(msg);
  }
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buf = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    const lines = buf.split("\n");
    buf = lines.pop();
    for (const line of lines) {
      if (!line.trim()) continue;
      let obj;
      try {
        obj = JSON.parse(line);
      } catch {
        continue;
      }
      if (obj.error) throw new Error(obj.error);
      const content = obj.message?.content;
      if (content) yield { content };
      if (obj.done) return;
    }
  }
}

// Ask the model to formulate the single best grounding query for this message.
// A person's name → search the person; a math problem → search the method; etc.
export async function generateQuery({ model, userText, lastAssistant }) {
  const f = await getFetch();
  const res = await f(`${BASE}/api/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      stream: false,
      options: { temperature: 0.2, num_predict: 48 },
      messages: [
        {
          role: "system",
          content:
            "You turn a user's chat message into ONE web search query that would gather the most useful " +
            "grounding context before answering. Decide the right kind of query yourself: for a person, " +
            "company, or product, search the name; for news or anything time-sensitive, search the topic " +
            "with the current year; for a how-to or math problem, search the method or concept; for a " +
            "coding error, search the error message. Reply with the query text ONLY — no quotes, no " +
            "explanation, one line.",
        },
        ...(lastAssistant
          ? [{ role: "system", content: `For context, your previous reply was about: ${lastAssistant.slice(0, 300)}` }]
          : []),
        { role: "user", content: userText.slice(0, 1500) },
      ],
    }),
    signal: AbortSignal.timeout(30000),
  });
  if (!res.ok) throw new Error(`query generation failed (${res.status})`);
  const data = await res.json();
  let q = (data.message?.content || "").split("\n")[0].trim();
  q = q.replace(/^["'`]+|["'`]+$/g, "").replace(/^(search|query):\s*/i, "").trim();
  if (!q || q.length > 160) q = userText.slice(0, 120);
  return q;
}

export function systemPrompt({ studyMode }) {
  const today = new Date().toLocaleDateString("en-US", {
    year: "numeric", month: "long", day: "numeric",
  });
  let p =
    "You are a helpful assistant running locally on the user's computer. " +
    "Be genuinely useful without the fluff: clear, warm, and direct. " +
    "Format answers with Markdown when it helps (headings, lists, tables, code blocks with language tags, " +
    "and LaTeX math in $...$ or $$...$$ when writing equations). " +
    `Today's date is ${today}.`;
  if (studyMode) {
    p +=
      "\n\nSTUDY MODE is on: act as a patient tutor. Break concepts into steps, check understanding " +
      "with short questions, use worked examples, and don't just hand over final answers to homework — " +
      "guide the user to reach them.";
  }
  return p;
}