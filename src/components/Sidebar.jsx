import React, { useState, useRef, useEffect } from "react";
import {
  PanelIcon, PencilIcon, SearchIcon, FolderPlusIcon, ExtIcon,
  DotsIcon, TrashIcon, FolderIcon,
} from "./Icons.jsx";

function ChatRow({ chat, active, projects, onOpen, onRename, onDelete, onMoveToProject }) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [renaming, setRenaming] = useState(false);
  const [draft, setDraft] = useState(chat.title);
  const ref = useRef(null);

  useEffect(() => {
    if (!menuOpen) return;
    const close = (e) => {
      if (ref.current && !ref.current.contains(e.target)) setMenuOpen(false);
    };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [menuOpen]);

  if (renaming) {
    return (
      <div className="chat-row active" ref={ref}>
        <input
          autoFocus
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onBlur={() => { onRename(chat.id, draft.trim() || chat.title); setRenaming(false); }}
          onKeyDown={(e) => {
            if (e.key === "Enter") { onRename(chat.id, draft.trim() || chat.title); setRenaming(false); }
            if (e.key === "Escape") setRenaming(false);
          }}
          style={{
            flex: 1, background: "none", border: "none", outline: "none",
            color: "var(--text-primary)", fontSize: 14, userSelect: "text",
          }}
        />
      </div>
    );
  }

  return (
    <div className={`chat-row ${active ? "active" : ""}`} ref={ref} onClick={() => onOpen(chat.id)} role="button">
      <span className="title">{chat.title}</span>
      <button
        className="row-menu-btn"
        onClick={(e) => { e.stopPropagation(); setMenuOpen(!menuOpen); }}
      >
        <DotsIcon size={15} />
      </button>
      {menuOpen && (
        <div className="row-menu" onClick={(e) => e.stopPropagation()}>
          <button onClick={() => { setMenuOpen(false); setDraft(chat.title); setRenaming(true); }}>
            <PencilIcon size={14} /> Rename
          </button>
          {projects.map((p) => (
            <button key={p.id} onClick={() => { setMenuOpen(false); onMoveToProject(chat.id, chat.projectId === p.id ? null : p.id); }}>
              <FolderIcon size={14} /> {chat.projectId === p.id ? `Remove from ${p.name}` : `Move to ${p.name}`}
            </button>
          ))}
          <button className="danger" onClick={() => { setMenuOpen(false); onDelete(chat.id); }}>
            <TrashIcon size={14} /> Delete
          </button>
        </div>
      )}
    </div>
  );
}

export default function Sidebar({
  collapsed, onToggle, chats, projects, activeChatId, view,
  onNewChat, onOpenSearch, onOpenProjects, onOpenChat, onRenameChat, onDeleteChat,
  onMoveToProject, onOpenSettings, onOpenTeamTrees,
}) {
  const recent = chats.filter((c) => !c.projectId);
  return (
    <aside className={`sidebar ${collapsed ? "collapsed" : ""}`}>
      <div className="sidebar-header drag-region" data-tauri-drag-region>
        <span className="wordmark" data-tauri-drag-region>PlantGPT</span>
        <button className="icon-btn" onClick={onToggle} title={collapsed ? "Expand sidebar" : "Collapse sidebar"}>
          <PanelIcon />
        </button>
      </div>

      <nav className="sidebar-nav">
        <button className="nav-item" onClick={onNewChat}>
          <PencilIcon /> <span>New chat</span>
        </button>
        <button className="nav-item" onClick={onOpenSearch}>
          <SearchIcon /> <span>Search chats</span>
        </button>
        <button className={`nav-item ${view === "projects" ? "active" : ""}`} onClick={onOpenProjects}>
          <FolderPlusIcon /> <span>Projects</span>
        </button>
      </nav>

      <div className="chats-section">
        {recent.length > 0 && <div className="chats-label">Chats</div>}
        {recent.map((c) => (
          <ChatRow
            key={c.id}
            chat={c}
            projects={projects}
            active={c.id === activeChatId && view === "chat"}
            onOpen={onOpenChat}
            onRename={onRenameChat}
            onDelete={onDeleteChat}
            onMoveToProject={onMoveToProject}
          />
        ))}
      </div>

      <div className="sidebar-footer">
        <button className="discord-row" onClick={onOpenTeamTrees} title="Donate $1 = plant 1 real tree">
          <span style={{ fontSize: 16, lineHeight: 1 }}>🌳</span> Plant a tree · TeamTrees <ExtIcon size={13} className="ext" />
        </button>
        <button className="green-cta" onClick={onOpenSettings}>Settings</button>
      </div>
    </aside>
  );
}
