import React, { useState, useEffect, useRef, useCallback } from "react";
import Sidebar from "./components/Sidebar.jsx";
import Composer from "./components/Composer.jsx";
import Markdown from "./components/Markdown.jsx";
import ImpactDrawer from "./components/ImpactDrawer.jsx";
import SearchModal from "./components/SearchModal.jsx";
import SettingsModal from "./components/SettingsModal.jsx";
import ProjectsView from "./components/ProjectsView.jsx";
import {
  CopyIcon, ThumbUpIcon, ThumbDownIcon, ShareIcon, RefreshIcon,
  ArrowDownIcon, CheckIcon, GlobeIcon,
} from "./components/Icons.jsx";
import { store, uid } from "./lib/store.js";
import { ollamaHealth, streamChat, systemPrompt, generateQuery } from "./lib/ollama.js";
import { webSearch as ddgSearch, searchContextMessage, readTopPages, pagesContextMessage } from "./lib/search.js";

const isTauri = () => typeof window !== "undefined" && !!window.__TAURI_INTERNALS__;

function openExternal(href) {
  if (isTauri()) {
    import("@tauri-apps/plugin-opener").then(({ openUrl }) => openUrl(href));
  } else {
    window.open(href, "_blank", "noopener");
  }
}

function AssistantActions({ msg, onCopy, onLike, onDislike, onShare, onRegen, canRegen }) {
  const [copied, setCopied] = useState(false);
  return (
    <div className="msg-actions">
      <button className="act" title="Copy" onClick={() => { onCopy(); setCopied(true); setTimeout(() => setCopied(false), 1200); }}>
        {copied ? <CheckIcon size={16} /> : <CopyIcon size={16} />}
      </button>
      <button className={`act ${msg.liked ? "on" : ""}`} title="Good response" onClick={onLike}>
        <ThumbUpIcon size={16} />
      </button>
      <button className={`act ${msg.disliked ? "on" : ""}`} title="Bad response" onClick={onDislike}>
        <ThumbDownIcon size={16} />
      </button>
      <button className="act" title="Share" onClick={onShare}>
        <ShareIcon size={16} />
      </button>
      {canRegen && (
        <button className="act" title="Regenerate" onClick={onRegen}>
          <RefreshIcon size={16} />
        </button>
      )}
    </div>
  );
}

export default function App() {
  const [settings, setSettings] = useState(store.loadSettings);
  const [chats, setChats] = useState(store.loadChats);
  const [projects, setProjects] = useState(store.loadProjects);
  const [impact, setImpact] = useState(store.loadImpact);
  const [activeChatId, setActiveChatId] = useState(null);
  const [view, setView] = useState("chat");
  const [collapsed, setCollapsed] = useState(false);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [streaming, setStreaming] = useState(false);
  const [searching, setSearching] = useState(null); // null | { query }
  const [attachments, setAttachments] = useState([]);
  const [toast, setToast] = useState(null);
  const [health, setHealth] = useState({ running: true, models: [] });
  const [showJump, setShowJump] = useState(false);

  const abortRef = useRef(null);
  const threadRef = useRef(null);
  const toastTimer = useRef(null);

  const showToast = useCallback((t) => {
    setToast(t);
    clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(null), 2600);
  }, []);

  // persistence
  useEffect(() => store.saveChats(chats), [chats]);
  useEffect(() => store.saveProjects(projects), [projects]);
  useEffect(() => store.saveImpact(impact), [impact]);
  useEffect(() => store.saveSettings(settings), [settings]);

  // theme
  useEffect(() => {
    const apply = () => {
      const mode =
        settings.theme === "system"
          ? window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark"
          : settings.theme;
      document.documentElement.dataset.theme = mode;
    };
    apply();
    const mq = window.matchMedia("(prefers-color-scheme: light)");
    mq.addEventListener("change", apply);
    return () => mq.removeEventListener("change", apply);
  }, [settings.theme]);

  // macOS traffic-light inset
  useEffect(() => {
    if (isTauri() && navigator.userAgent.includes("Mac")) {
      document.documentElement.classList.add("macos-inset");
    }
  }, []);

  // ollama health + default model
  useEffect(() => {
    ollamaHealth().then((h) => {
      setHealth(h);
      if (h.models.length && !h.models.includes(settings.model)) {
        setSettings((s) => ({ ...s, model: h.models.includes(s.model) ? s.model : h.models[0] }));
      }
    });
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // shortcuts
  useEffect(() => {
    const onKey = (e) => {
      const mod = e.metaKey || e.ctrlKey;
      if (mod && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setSearchOpen((v) => !v);
      } else if (mod && e.key.toLowerCase() === "j") {
        e.preventDefault();
        newChat();
      } else if (e.key === "Escape") {
        setDrawerOpen(false);
        setSearchOpen(false);
        setSettingsOpen(false);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const activeChat = chats.find((c) => c.id === activeChatId) || null;

  // scroll handling
  useEffect(() => {
    const el = threadRef.current;
    if (!el) return;
    const onScroll = () => {
      setShowJump(el.scrollHeight - el.scrollTop - el.clientHeight > 140);
    };
    el.addEventListener("scroll", onScroll);
    onScroll();
    return () => el.removeEventListener("scroll", onScroll);
  }, [activeChatId, view]);

  const scrollToBottom = (smooth = true) => {
    const el = threadRef.current;
    if (el) el.scrollTo({ top: el.scrollHeight, behavior: smooth ? "smooth" : "auto" });
  };

  useEffect(() => {
    const el = threadRef.current;
    if (el && streaming && el.scrollHeight - el.scrollTop - el.clientHeight < 220) {
      el.scrollTop = el.scrollHeight;
    }
  }, [chats, streaming]);

  const patchChat = useCallback((chatId, fn) => {
    setChats((cs) => cs.map((c) => (c.id === chatId ? fn(c) : c)));
  }, []);

  function newChat(projectId = null) {
    abortRef.current?.abort();
    setActiveChatId(null);
    setView("chat");
    setAttachments([]);
    if (projectId) {
      // pre-create so it lands in the project
      const chat = {
        id: uid(), title: "New chat", projectId,
        createdAt: Date.now(), updatedAt: Date.now(), messages: [],
      };
      setChats((cs) => [chat, ...cs]);
      setActiveChatId(chat.id);
    }
  }

  async function runAssistant(chatId, apiMessages) {
    const asstId = uid();
    patchChat(chatId, (c) => ({
      ...c,
      updatedAt: Date.now(),
      messages: [...c.messages, { id: asstId, role: "assistant", content: "", model: settings.model }],
    }));
    setStreaming(true);
    const ac = new AbortController();
    abortRef.current = ac;
    let acc = "";
    try {
      for await (const chunk of streamChat({
        model: settings.model,
        messages: apiMessages,
        signal: ac.signal,
      })) {
        acc += chunk.content;
        const snapshot = acc;
        patchChat(chatId, (c) => ({
          ...c,
          messages: c.messages.map((m) => (m.id === asstId ? { ...m, content: snapshot } : m)),
        }));
      }
    } catch (err) {
      if (err.name !== "AbortError") {
        const msg = `⚠️ ${err.message || "Something went wrong talking to Ollama."}`;
        patchChat(chatId, (c) => ({
          ...c,
          messages: c.messages.map((m) =>
            m.id === asstId ? { ...m, content: acc ? acc + `\n\n${msg}` : msg } : m
          ),
        }));
      }
    } finally {
      setStreaming(false);
      abortRef.current = null;
    }
  }

  function buildApiMessages(chat, extraContext) {
    const msgs = [{ role: "system", content: systemPrompt({ studyMode: settings.studyMode }) }];
    for (const ctx of [].concat(extraContext || [])) {
      if (ctx) msgs.push({ role: "system", content: ctx });
    }
    for (const m of chat.messages) {
      if (m.role === "user") {
        const entry = { role: "user", content: m.content };
        if (m.images?.length) {
          entry.images = m.images.map((d) => d.split(",")[1]);
        }
        if (m.fileText) entry.content += `\n\n${m.fileText}`;
        msgs.push(entry);
      } else if (m.role === "assistant" && m.content) {
        msgs.push({ role: "assistant", content: m.content });
      }
    }
    return msgs;
  }

  async function sendMessage(text) {
    if (!health.running) {
      const h = await ollamaHealth();
      setHealth(h);
      if (!h.running) {
        showToast("Ollama isn't running — start it with: brew services start ollama");
        return;
      }
      if (h.models.length && !h.models.includes(settings.model)) {
        setSettings((s) => ({ ...s, model: h.models[0] }));
      }
    }
    if (!settings.model) {
      const h = await ollamaHealth();
      if (h.models.length) {
        setSettings((s) => ({ ...s, model: h.models[0] }));
      } else {
        showToast("No local models — run: ollama pull qwen2.5:3b");
        return;
      }
    }

    let chatId = activeChatId;
    let isNew = false;
    if (!chatId || view !== "chat") {
      isNew = !chatId;
      if (!chatId) {
        chatId = uid();
        const chat = {
          id: chatId, title: text.slice(0, 46) || "New chat", projectId: null,
          createdAt: Date.now(), updatedAt: Date.now(), messages: [],
        };
        setChats((cs) => [chat, ...cs]);
        setActiveChatId(chatId);
      }
      setView("chat");
    }

    const images = attachments.filter((a) => a.kind === "image").map((a) => a.dataUrl);
    const textFiles = attachments.filter((a) => a.kind === "text");
    const fileText = textFiles.length
      ? textFiles.map((f) => `--- Attached file: ${f.name} ---\n${f.text}`).join("\n\n")
      : undefined;

    const userMsg = {
      id: uid(), role: "user", content: text,
      ...(images.length ? { images } : {}),
      ...(fileText ? { fileText } : {}),
    };
    setAttachments([]);

    // build against the freshest chat state
    let apiMessages = null;
    setChats((cs) => {
      const next = cs.map((c) => {
        if (c.id !== chatId) return c;
        const updated = {
          ...c,
          title: c.messages.length === 0 ? text.slice(0, 46) || c.title : c.title,
          updatedAt: Date.now(),
          messages: [...c.messages, userMsg],
        };
        return updated;
      });
      return next;
    });
    const newCount = impact.messages + 1;
    setImpact((i) => ({ ...i, messages: i.messages + 1 }));

    // Always-on grounding: the model formulates the query, we fetch, results become context.
    const extraContext = [];
    if (settings.webSearch) {
      setSearching({ query: "" });
      try {
        const lastAssistant = activeChat?.messages.filter((m) => m.role === "assistant").pop()?.content;
        const query = await generateQuery({ model: settings.model, userText: text, lastAssistant });
        setSearching({ query });
        const results = await ddgSearch(query);
        if (results.length) {
          extraContext.push(searchContextMessage(query, results));
          setSearching({ query, reading: true });
          const pages = await readTopPages(results, 2);
          if (pages.length) extraContext.push(pagesContextMessage(pages));
        }
      } catch {
        showToast("Web grounding failed — answering without it");
      }
      setSearching(null);
    }

    // read back the chat we just updated
    const chatNow = await new Promise((resolve) => {
      setChats((cs) => {
        resolve(cs.find((c) => c.id === chatId));
        return cs;
      });
    });
    apiMessages = buildApiMessages(chatNow, extraContext);
    await runAssistant(chatId, apiMessages);

    // Built-in TeamTrees nudge: every 50 prompts, drop a donate card into the thread.
    if (newCount % 50 === 0) {
      patchChat(chatId, (c) => ({
        ...c,
        messages: [...c.messages, { id: uid(), role: "donation", count: newCount }],
      }));
    }
  }

  async function regenerate() {
    if (!activeChat || streaming) return;
    const msgs = [...activeChat.messages];
    while (msgs.length && msgs[msgs.length - 1].role !== "user") msgs.pop();
    if (!msgs.length) return;
    patchChat(activeChat.id, (c) => ({ ...c, messages: msgs }));
    const apiMessages = buildApiMessages({ ...activeChat, messages: msgs }, null);
    await runAssistant(activeChat.id, apiMessages);
  }

  async function handleAttach(files) {
    const next = [];
    for (const f of files) {
      if (f.type.startsWith("image/")) {
        const dataUrl = await new Promise((res) => {
          const r = new FileReader();
          r.onload = () => res(r.result);
          r.readAsDataURL(f);
        });
        next.push({ kind: "image", name: f.name, dataUrl });
      } else {
        if (f.size > 512 * 1024) {
          showToast(`${f.name} is too big (512KB max for text files)`);
          continue;
        }
        const text = await f.text();
        next.push({ kind: "text", name: f.name, text });
      }
    }
    setAttachments((a) => [...a, ...next]);
  }

  function shareImpact() {
    const trees = Math.floor(impact.messages / 100);
    navigator.clipboard.writeText(
      `I've sent ${impact.messages} messages on PlantGPT and earned ${trees} tree${trees === 1 ? "" : "s"} 🌳 — $1 each at teamtrees.org makes them real.`
    );
    setImpact((i) => ({ ...i, shares: i.shares + 1 }));
    showToast("Impact copied to clipboard");
  }

  const setupProblem = !health.running
    ? { text: "Ollama isn't running.", cmd: "brew services start ollama" }
    : health.models.length === 0
      ? { text: "No local models installed yet.", cmd: "ollama pull qwen2.5:3b" }
      : null;

  const composerProps = {
    streaming: streaming || !!searching,
    webSearch: settings.webSearch,
    studyMode: settings.studyMode,
    attachments,
    onSend: sendMessage,
    onStop: () => abortRef.current?.abort(),
    onToggleWebSearch: () => {
      setSettings((s) => {
        showToast(s.webSearch ? "Web grounding off" : "Web grounding on — every reply gets fresh search context");
        return { ...s, webSearch: !s.webSearch };
      });
    },
    onToggleStudyMode: () => {
      setSettings((s) => {
        showToast(s.studyMode ? "Study mode off" : "Study mode on");
        return { ...s, studyMode: !s.studyMode };
      });
    },
    onAttach: handleAttach,
    onRemoveAttachment: (i) => setAttachments((a) => a.filter((_, j) => j !== i)),
    onToast: showToast,
  };

  return (
    <div className="app">
      <Sidebar
        collapsed={collapsed}
        onToggle={() => setCollapsed(!collapsed)}
        chats={chats}
        projects={projects}
        activeChatId={activeChatId}
        view={view}
        onNewChat={() => newChat()}
        onOpenSearch={() => setSearchOpen(true)}
        onOpenProjects={() => setView(view === "projects" ? "chat" : "projects")}
        onOpenChat={(id) => { setActiveChatId(id); setView("chat"); }}
        onRenameChat={(id, title) => patchChat(id, (c) => ({ ...c, title }))}
        onDeleteChat={(id) => {
          setChats((cs) => cs.filter((c) => c.id !== id));
          if (id === activeChatId) setActiveChatId(null);
        }}
        onMoveToProject={(id, projectId) => patchChat(id, (c) => ({ ...c, projectId }))}
        onOpenSettings={() => setSettingsOpen(true)}
        onOpenTeamTrees={() => openExternal("https://teamtrees.org")}
      />

      <main className="main">
        <div className="topbar drag-region" data-tauri-drag-region>
          <button className="tree-btn" title="Your impact" onClick={() => setDrawerOpen(true)}>
            🌲
          </button>
        </div>

        {view === "projects" ? (
          <ProjectsView
            projects={projects}
            chats={chats}
            onCreateProject={(name) => {
              setProjects((ps) => [...ps, { id: uid(), name, createdAt: Date.now() }]);
            }}
            onDeleteProject={(id) => {
              setProjects((ps) => ps.filter((p) => p.id !== id));
              setChats((cs) => cs.map((c) => (c.projectId === id ? { ...c, projectId: null } : c)));
            }}
            onOpenChat={(id) => { setActiveChatId(id); setView("chat"); }}
            onNewChatInProject={(pid) => newChat(pid)}
          />
        ) : !activeChat || activeChat.messages.length === 0 ? (
          <>
            <div className="empty-wrap">
              <div className="earth">🌍</div>
              <h1 className="hello">What can I help with?</h1>
              {setupProblem && (
                <div className="setup-banner">
                  <span>
                    {setupProblem.text} Run <code>{setupProblem.cmd}</code>
                  </span>
                  <button
                    className="retry"
                    onClick={async () => {
                      const h = await ollamaHealth();
                      setHealth(h);
                      if (h.running && h.models.length) {
                        if (!h.models.includes(settings.model)) {
                          setSettings((s) => ({ ...s, model: h.models[0] }));
                        }
                        showToast("Connected to Ollama");
                      }
                    }}
                  >
                    Retry
                  </button>
                </div>
              )}
              <Composer docked={false} {...composerProps} />
            </div>
            <div className="whatis">
              <button onClick={() => setDrawerOpen(true)}>What is PlantGPT?</button>
            </div>
          </>
        ) : (
          <>
            <div className="thread" ref={threadRef}>
              <div className="thread-inner">
                {activeChat.messages.map((m, idx) =>
                  m.role === "donation" ? (
                    <div className="donate-card" key={m.id}>
                      <div className="donate-head">
                        <span className="donate-logo">🌳</span>
                        <span className="donate-brand">TeamTrees</span>
                        <span className="donate-tag">{m.count} prompts</span>
                      </div>
                      <p className="donate-desc">
                        You've sent {m.count} prompts — that's {Math.floor(m.count / 100) > 0
                          ? `${Math.floor(m.count / 100)} tree${Math.floor(m.count / 100) === 1 ? "" : "s"} earned`
                          : "halfway to your first tree"}. $1 plants a real one through MrBeast's TeamTrees.
                      </p>
                      <button
                        className="donate-btn"
                        onClick={() => openExternal("https://teamtrees.org")}
                      >
                        Donate $1 →
                      </button>
                    </div>
                  ) : m.role === "user" ? (
                    <div className="msg-user" key={m.id}>
                      <div className="bubble">
                        {m.images?.map((src, i) => (
                          <img className="sent-img" src={src} key={i} alt="" />
                        ))}
                        {m.content}
                      </div>
                    </div>
                  ) : (
                    <div className="msg-assistant" key={m.id}>
                      {m.content ? (
                        <Markdown text={m.content} />
                      ) : (
                        <span className="blink-dot" />
                      )}
                      {!streaming && m.content && (
                        <AssistantActions
                          msg={m}
                          canRegen={idx === activeChat.messages.length - 1}
                          onCopy={() => navigator.clipboard.writeText(m.content)}
                          onLike={() =>
                            patchChat(activeChat.id, (c) => ({
                              ...c,
                              messages: c.messages.map((x) =>
                                x.id === m.id ? { ...x, liked: !x.liked, disliked: false } : x
                              ),
                            }))
                          }
                          onDislike={() =>
                            patchChat(activeChat.id, (c) => ({
                              ...c,
                              messages: c.messages.map((x) =>
                                x.id === m.id ? { ...x, disliked: !x.disliked, liked: false } : x
                              ),
                            }))
                          }
                          onShare={() => {
                            navigator.clipboard.writeText(m.content);
                            showToast("Response copied");
                          }}
                          onRegen={regenerate}
                        />
                      )}
                    </div>
                  )
                )}
                {searching && (
                  <div className="searching-note">
                    <GlobeIcon size={15} />
                    {searching.reading
                      ? "Reading top results..."
                      : searching.query
                        ? <>Searching: “{searching.query}”</>
                        : "Writing search query..."}
                  </div>
                )}
              </div>
            </div>
            <div className="composer-zone docked" style={{ position: "relative" }}>
              {showJump && (
                <button className="jump-btn" onClick={() => scrollToBottom()}>
                  <ArrowDownIcon size={16} />
                </button>
              )}
            </div>
            <Composer docked {...composerProps} />
            <div className="made-mistakes">
              PlantGPT can make mistakes.{" "}
              <button onClick={() => setDrawerOpen(true)}>Learn more here.</button>
            </div>
          </>
        )}
      </main>

      <ImpactDrawer
        open={drawerOpen}
        onClose={() => setDrawerOpen(false)}
        impact={impact}
        chats={chats}
        projects={projects}
        username={settings.username}
        onShare={shareImpact}
        onToast={showToast}
        onOpenExternal={openExternal}
      />
      <SearchModal
        open={searchOpen}
        chats={chats}
        onClose={() => setSearchOpen(false)}
        onNewChat={() => newChat()}
        onOpenChat={(id) => { setActiveChatId(id); setView("chat"); }}
      />
      <SettingsModal
        open={settingsOpen}
        settings={settings}
        onClose={() => setSettingsOpen(false)}
        onSave={(s) => setSettings(s)}
      />
      {toast && <div className="toast">{toast}</div>}
    </div>
  );
}
