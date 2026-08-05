import React, { useState, useEffect, useRef } from "react";
import { SearchIcon, XIcon, PencilIcon } from "./Icons.jsx";

function ago(ts) {
  const d = Date.now() - ts;
  const m = Math.floor(d / 60000);
  if (m < 1) return "now";
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h`;
  return `${Math.floor(h / 24)}d`;
}

export default function SearchModal({ open, chats, onClose, onNewChat, onOpenChat }) {
  const [q, setQ] = useState("");
  const inputRef = useRef(null);

  useEffect(() => {
    if (open) {
      setQ("");
      setTimeout(() => inputRef.current?.focus(), 30);
    }
  }, [open]);

  if (!open) return null;

  const needle = q.trim().toLowerCase();
  const results = needle
    ? chats.filter(
        (c) =>
          c.title.toLowerCase().includes(needle) ||
          c.messages.some((m) => typeof m.content === "string" && m.content.toLowerCase().includes(needle))
      )
    : chats;

  return (
    <div className="modal-overlay" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="search-modal">
        <div className="search-head">
          <SearchIcon size={19} />
          <input
            ref={inputRef}
            placeholder="Search chats..."
            value={q}
            onChange={(e) => setQ(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Escape") onClose();
              if (e.key === "Enter" && results.length > 0) {
                onOpenChat(results[0].id);
                onClose();
              }
            }}
          />
          <button className="icon-btn" onClick={onClose}><XIcon size={16} /></button>
        </div>
        <div className="search-body">
          <button className="search-item" onClick={() => { onNewChat(); onClose(); }}>
            <PencilIcon size={16} /> New chat
          </button>
          {results.length === 0 ? (
            <div className="search-empty">
              {chats.length === 0 ? "No conversations yet" : "No matches"}
            </div>
          ) : (
            results.map((c) => (
              <button className="search-item" key={c.id} onClick={() => { onOpenChat(c.id); onClose(); }}>
                <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{c.title}</span>
                <span className="when">{ago(c.updatedAt)}</span>
              </button>
            ))
          )}
        </div>
      </div>
    </div>
  );
}
