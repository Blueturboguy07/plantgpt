// publik API as the chat engine, next to Ollama. The install key never reaches this webview:
// the Rust side (src-tauri/src/publik_chat.rs) runs each request and streams the reply back
// as "publik-chat" events. Outside Tauri (vite dev in a browser) there is no publik engine.

import { queryMessages, cleanQuery } from "./ollama.js";

const isTauri = () => typeof window !== "undefined" && !!window.__TAURI_INTERNALS__;

// A tier, never a vendor model name.
export const PUBLIK_MODEL = "publik-balanced";
export const PUBLIK_FAST_MODEL = "publik-fast";

// { kind: "publik" | "own" | "needs_own_key" }. Anything but "publik" means Ollama on this computer.
export async function publikProvider() {
  if (!isTauri()) return { kind: "needs_own_key" };
  try {
    const { invoke } = await import("@tauri-apps/api/core");
    return await invoke("publik_provider");
  } catch {
    return { kind: "needs_own_key" };
  }
}

// "publik", "own_key", or null (the gate asks again at the next start).
export async function publikSetChoice(choice) {
  if (!isTauri()) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("publik_set_choice", { choice });
}

// Ollama-style messages ({role, content, images?: [data URL]}) to OpenAI chat messages.
export function toChatMessages(messages) {
  return messages.map((m) => {
    if (m.role === "user" && m.images?.length) {
      return {
        role: "user",
        content: [
          { type: "text", text: m.content },
          ...m.images.map((url) => ({ type: "image_url", image_url: { url } })),
        ],
      };
    }
    return { role: m.role, content: m.content };
  });
}

// Streams { content } chunks, like streamChat in ollama.js. Throws with the API's message
// (plus the one top-up link on a 402). Aborting the signal stops the request.
export async function* streamPublikChat({ messages, signal, model = PUBLIK_MODEL }) {
  const { invoke } = await import("@tauri-apps/api/core");
  const { listen } = await import("@tauri-apps/api/event");
  const id = Math.random().toString(36).slice(2) + Date.now().toString(36);
  const queue = [];
  let wake = null;
  let finished = false;
  let failure = null;
  const push = (item) => {
    queue.push(item);
    if (wake) {
      const w = wake;
      wake = null;
      w();
    }
  };
  const unlisten = await listen("publik-chat", (e) => {
    const p = e.payload;
    if (!p || p.id !== id) return;
    if (p.error) {
      failure = new Error(p.top_up_url ? `${p.error} ${p.top_up_url}` : p.error);
    } else if (p.delta) {
      push(p.delta);
    }
    if (p.done || p.error) {
      finished = true;
      push(null);
    }
  });
  const stop = () => {
    invoke("publik_chat_stop", { id }).catch(() => {});
    finished = true;
    push(null);
  };
  signal?.addEventListener("abort", stop, { once: true });
  try {
    await invoke("publik_chat", { id, body: { model, messages: toChatMessages(messages) } });
    for (;;) {
      if (queue.length) {
        const item = queue.shift();
        if (item === null) break;
        yield { content: item };
        continue;
      }
      if (finished) break;
      await new Promise((resolve) => {
        wake = resolve;
      });
    }
    if (failure && !signal?.aborted) throw failure;
  } finally {
    signal?.removeEventListener("abort", stop);
    unlisten();
  }
}

// One whole reply, for a short non-streamed call.
export async function publikComplete({ messages, model = PUBLIK_FAST_MODEL }) {
  let out = "";
  for await (const chunk of streamPublikChat({ messages, model })) out += chunk.content;
  return out;
}

// The grounding query through publik: the same prompt as generateQuery in ollama.js.
export async function publikGenerateQuery({ userText, lastAssistant }) {
  const text = await publikComplete({ messages: queryMessages({ userText, lastAssistant }) });
  return cleanQuery(text, userText);
}
