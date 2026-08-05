import React, { useRef, useState, useEffect } from "react";
import {
  PlusIcon, MicIcon, ArrowUpIcon, StopIcon, PaperclipIcon, GlobeIcon,
  BookIcon, ImageIcon, CheckIcon, XIcon,
} from "./Icons.jsx";

export default function Composer({
  docked, streaming, webSearch, studyMode, attachments,
  onSend, onStop, onToggleWebSearch, onToggleStudyMode,
  onAttach, onRemoveAttachment, onToast,
}) {
  const [text, setText] = useState("");
  const [toolsOpen, setToolsOpen] = useState(false);
  const taRef = useRef(null);
  const fileRef = useRef(null);
  const wrapRef = useRef(null);

  useEffect(() => {
    const ta = taRef.current;
    if (!ta) return;
    ta.style.height = "auto";
    ta.style.height = Math.min(ta.scrollHeight, 196) + "px";
  }, [text]);

  useEffect(() => {
    if (!toolsOpen) return;
    const close = (e) => {
      if (wrapRef.current && !wrapRef.current.contains(e.target)) setToolsOpen(false);
    };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [toolsOpen]);

  const canSend = (text.trim().length > 0 || attachments.length > 0) && !streaming;

  const send = () => {
    if (!canSend) return;
    const t = text;
    setText("");
    onSend(t.trim());
  };

  return (
    <div className={`composer-zone ${docked ? "docked" : ""}`}>
      {attachments.length > 0 && (
        <div className="attach-chips">
          {attachments.map((a, i) => (
            <span className="attach-chip" key={i}>
              {a.kind === "image" ? <img src={a.dataUrl} alt="" /> : <PaperclipIcon size={14} />}
              {a.name}
              <button onClick={() => onRemoveAttachment(i)}><XIcon size={13} /></button>
            </span>
          ))}
        </div>
      )}
      <div className="composer" ref={wrapRef}>
        <button
          className={`round-btn plus-btn ${toolsOpen ? "open" : ""}`}
          title="Tools"
          onClick={() => setToolsOpen(!toolsOpen)}
        >
          <PlusIcon size={20} />
        </button>

        {toolsOpen && (
          <div className={`tools-menu ${docked ? "above" : "below"}`}>
            <button
              className="tool-item"
              onClick={() => { setToolsOpen(false); fileRef.current?.click(); }}
            >
              <PaperclipIcon /> Add photos & files
            </button>
            <button className="tool-item" onClick={() => { onToggleWebSearch(); setToolsOpen(false); }}>
              <GlobeIcon /> Web search
              {webSearch && <CheckIcon size={16} className="check" />}
            </button>
            <div className="tools-divider" />
            <button className="tool-item" onClick={() => { onToggleStudyMode(); setToolsOpen(false); }}>
              <BookIcon /> Study mode
              {studyMode && <CheckIcon size={16} className="check" />}
            </button>
            <button className="tool-item" disabled title="Not available with local models yet">
              <ImageIcon /> Create image
            </button>
          </div>
        )}

        <textarea
          ref={taRef}
          rows={1}
          placeholder="Ask anything..."
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              send();
            }
          }}
        />

        <button
          className="round-btn"
          title="Voice input"
          onClick={() => onToast("Use macOS dictation: press the mic key (or fn twice) while typing")}
        >
          <MicIcon size={19} />
        </button>
        {streaming ? (
          <button className="round-btn send-btn" title="Stop" onClick={onStop}>
            <StopIcon size={18} />
          </button>
        ) : (
          <button className="round-btn send-btn" title="Send" disabled={!canSend} onClick={send}>
            <ArrowUpIcon size={19} />
          </button>
        )}

        <input
          ref={fileRef}
          type="file"
          multiple
          accept="image/png,image/jpeg,image/webp,image/gif,.txt,.md,.csv,.json,.js,.ts,.jsx,.tsx,.py,.rs,.html,.css,.java,.c,.cpp,.sh,.yaml,.yml,.toml"
          style={{ display: "none" }}
          onChange={(e) => {
            onAttach([...e.target.files]);
            e.target.value = "";
          }}
        />
      </div>
    </div>
  );
}
