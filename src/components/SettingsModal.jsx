import React, { useState, useEffect } from "react";
import { ollamaHealth } from "../lib/ollama.js";
import { isMacPlatform } from "../lib/platform.js";
import { publikSetChoice } from "../lib/publik.js";

export default function SettingsModal({ open, settings, onClose, onSave, provider, onProviderChange }) {
  const [draft, setDraft] = useState(settings);
  const [health, setHealth] = useState({ running: false, models: [] });
  const [checking, setChecking] = useState(false);

  const check = async () => {
    setChecking(true);
    const h = await ollamaHealth();
    setHealth(h);
    setChecking(false);
    return h;
  };

  useEffect(() => {
    if (open) {
      setDraft(settings);
      check();
    }
  }, [open]); // eslint-disable-line react-hooks/exhaustive-deps

  if (!open) return null;

  // The answer to the sign-in gate's "Choose how to pay for AI" screen.
  const engine = provider?.kind === "publik" ? "publik" : "own_key";
  const pick = async (choice) => {
    try {
      await publikSetChoice(choice);
    } catch {
      /* outside the desktop app there is nothing to store */
    }
    onProviderChange?.();
  };

  const models = health.models.length
    ? health.models
    : draft.model
      ? [draft.model]
      : [];

  return (
    <div className="modal-overlay" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="settings-modal">
        <h2>Settings</h2>
        <p className="settings-sub">PlantGPT opens with Sign in with publik and counts usage (app opened, active session). Replies come from your publik plan, or from Ollama on this computer at no cost.</p>

        <div className="field">
          <label>AI engine</label>
          <div className="seg">
            <button className={engine === "publik" ? "on" : ""} onClick={() => pick("publik")}>Your publik plan</button>
            <button className={engine === "own_key" ? "on" : ""} onClick={() => pick("own_key")}>Ollama on this computer</button>
          </div>
          <p className="settings-sub" style={{ marginTop: 8 }}>
            {engine === "publik"
              ? "Replies come from the publik API (publik-balanced) through your plan."
              : "Replies come from Ollama on this computer. No key is needed."}{" "}
            <button className="link-green" onClick={() => pick(null)}>Ask again at next start</button>
          </p>
        </div>

        <div className="field">
          <label>Local engine</label>
          <div className="ollama-status">
            <span className={`dot ${health.running ? "ok" : ""}`} />
            {checking
              ? "Checking Ollama..."
              : health.running
                ? `Ollama running · ${health.models.length} model${health.models.length === 1 ? "" : "s"} installed`
                : "Ollama is not running"}
            <button className="link-green" style={{ marginLeft: "auto" }} onClick={check}>Refresh</button>
          </div>
          {!health.running && !checking && (
            <p className="settings-sub" style={{ marginTop: 8 }}>
              {isMacPlatform() ? (
                <>Start it with <code style={{ userSelect: "text" }}>brew services start ollama</code></>
              ) : (
                "Open the Ollama app"
              )}
            </p>
          )}
          {health.running && health.models.length === 0 && (
            <p className="settings-sub" style={{ marginTop: 8 }}>
              No models yet — run <code style={{ userSelect: "text" }}>ollama pull qwen2.5:3b</code>
            </p>
          )}
        </div>

        <div className="field">
          <label>Model</label>
          <select
            value={draft.model}
            onChange={(e) => setDraft({ ...draft, model: e.target.value })}
          >
            {models.length === 0 && <option value="">No models installed</option>}
            {models.map((m) => (
              <option key={m} value={m}>{m}</option>
            ))}
          </select>
        </div>

        <div className="field">
          <label>Theme</label>
          <div className="seg">
            {[["dark", "Dark"], ["light", "Light"], ["system", "System"]].map(([k, label]) => (
              <button
                key={k}
                className={draft.theme === k ? "on" : ""}
                onClick={() => setDraft({ ...draft, theme: k })}
              >
                {label}
              </button>
            ))}
          </div>
        </div>

        <div className="field">
          <label>Username (shown on your impact card)</label>
          <input
            value={draft.username}
            onChange={(e) => setDraft({ ...draft, username: e.target.value.replace(/^@/, "") })}
            placeholder="user"
          />
        </div>

        <div className="settings-actions">
          <button className="btn-secondary" onClick={onClose}>Cancel</button>
          <button
            className="btn-primary"
            onClick={() => {
              const model = draft.model || health.models[0] || "";
              onSave({ ...draft, model });
              onClose();
            }}
          >
            Save
          </button>
        </div>
      </div>
    </div>
  );
}
