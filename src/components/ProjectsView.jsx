import React, { useState } from "react";
import { FolderIcon, PlusIcon, ChevronLeftIcon, TrashIcon } from "./Icons.jsx";

export default function ProjectsView({
  projects, chats, onCreateProject, onDeleteProject, onOpenChat, onNewChatInProject,
}) {
  const [name, setName] = useState("");
  const [openProject, setOpenProject] = useState(null);

  const create = () => {
    const n = name.trim();
    if (!n) return;
    onCreateProject(n);
    setName("");
  };

  if (openProject) {
    const project = projects.find((p) => p.id === openProject);
    if (!project) { setOpenProject(null); return null; }
    const projectChats = chats.filter((c) => c.projectId === project.id);
    return (
      <div className="projects-view">
        <div className="projects-inner">
          <div className="projects-head">
            <h1 style={{ display: "flex", alignItems: "center", gap: 10 }}>
              <button className="icon-btn" onClick={() => setOpenProject(null)}><ChevronLeftIcon /></button>
              {project.name}
            </h1>
            <button className="btn-primary" onClick={() => onNewChatInProject(project.id)}>
              New chat
            </button>
          </div>
          {projectChats.length === 0 ? (
            <div className="projects-empty">No chats in this project yet.</div>
          ) : (
            projectChats.map((c) => (
              <button className="project-card" key={c.id} onClick={() => onOpenChat(c.id)}>
                <span className="p-name">{c.title}</span>
                <span className="p-count">{c.messages.length} messages</span>
              </button>
            ))
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="projects-view">
      <div className="projects-inner">
        <div className="projects-head">
          <h1>Projects</h1>
        </div>
        <div className="new-project-row">
          <input
            placeholder="New project name..."
            value={name}
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && create()}
          />
          <button className="btn-primary" onClick={create}><PlusIcon size={16} /></button>
        </div>
        {projects.length === 0 ? (
          <div className="projects-empty">
            Group related chats into projects. Create your first one above.
          </div>
        ) : (
          projects.map((p) => {
            const count = chats.filter((c) => c.projectId === p.id).length;
            return (
              <div className="project-card" key={p.id} role="button" onClick={() => setOpenProject(p.id)} style={{ cursor: "pointer" }}>
                <FolderIcon className="p-icon" />
                <span className="p-name">{p.name}</span>
                <span className="p-count">{count} chat{count === 1 ? "" : "s"}</span>
                <button
                  className="icon-btn"
                  title="Delete project"
                  onClick={(e) => { e.stopPropagation(); onDeleteProject(p.id); }}
                >
                  <TrashIcon size={15} />
                </button>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
