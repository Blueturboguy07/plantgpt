import React, { useState } from "react";
import {
  ChevronLeftIcon, ChevronRightIcon, ShareIcon, PlusIcon, ExtIcon, MapIcon,
} from "./Icons.jsx";
import { computeImpact, badgeStates } from "../lib/store.js";

/* Isometric grass field, drawn as SVG (the real site uses a bitmap illustration). */
function IsoField() {
  const COLS = 8, ROWS = 8, TW = 34, TH = 17;
  const w = (COLS + ROWS) * (TW / 2);
  const h = (COLS + ROWS) * (TH / 2);
  const originX = ROWS * (TW / 2);
  const tiles = [];
  for (let r = 0; r < ROWS; r++) {
    for (let c = 0; c < COLS; c++) {
      const x = originX + (c - r) * (TW / 2);
      const y = (c + r) * (TH / 2);
      const light = (r + c) % 2 === 0;
      tiles.push(
        <polygon
          key={`${r}-${c}`}
          points={`${x},${y} ${x + TW / 2},${y + TH / 2} ${x},${y + TH} ${x - TW / 2},${y + TH / 2}`}
          fill={light ? "#a9d94f" : "#9ecf42"}
          stroke="#8fbf39"
          strokeWidth="0.6"
        />
      );
    }
  }
  const depth = 20;
  const leftFace = `0,${h / 2} ${originX - ROWS * (TW / 2) + COLS * (TW / 2)},${h} ${COLS * (TW / 2)},${h + depth} ${0 + 0},${h / 2 + depth}`;
  return (
    <svg className="field-svg" width={w} height={h + depth + 4} viewBox={`-2 -2 ${w + 4} ${h + depth + 8}`}>
      {/* dirt sides */}
      <polygon points={`0,${h / 2} ${COLS * (TW / 2)},${h} ${COLS * (TW / 2)},${h + depth} 0,${h / 2 + depth}`} fill="#7a5a3a" />
      <polygon points={`${w},${h / 2} ${COLS * (TW / 2)},${h} ${COLS * (TW / 2)},${h + depth} ${w},${h / 2 + depth}`} fill="#8b6a45" />
      {tiles}
    </svg>
  );
}

function BadgeSeal({ emoji, locked }) {
  // scalloped seal outline
  const R = 30, r = 2.6, N = 22, cx = 32, cy = 32;
  let d = "";
  for (let i = 0; i <= N * 2; i++) {
    const ang = (Math.PI * 2 * i) / (N * 2);
    const rad = R + (i % 2 === 0 ? r : -r);
    const x = cx + rad * Math.cos(ang);
    const y = cy + rad * Math.sin(ang);
    d += (i === 0 ? "M" : "L") + x.toFixed(1) + " " + y.toFixed(1);
  }
  d += "Z";
  return (
    <div className={`badge-seal ${locked ? "locked" : ""}`}>
      <svg width="64" height="64" viewBox="0 0 64 64">
        <path d={d} fill={locked ? "#4a4a4a" : "#e8f3e9"} />
        <circle cx="32" cy="32" r="24" fill="none" stroke={locked ? "#5a5a5a" : "#b7d8ba"} strokeWidth="1.4" strokeDasharray="3 3" />
      </svg>
      <span className="emoji">{emoji}</span>
    </div>
  );
}

const EMOJI_ROWS_BIG = [
  "🪨🪨🪨🪨🪨🪨🪨🪨🪨🪨",
  "🪨🪨🪨🪨🪨🪨🪨🪨🪨🪨",
  "⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡",
  "💧💧💧💧💧💧💧💧💧💧",
  "💧💧💧💧💧💧💧💧💧💧",
];

export default function ImpactDrawer({
  open, onClose, impact, chats, projects, username, onShare, onToast, onOpenExternal,
}) {
  const [tab, setTab] = useState("about");
  if (!open) return null;
  const s = computeImpact(impact);
  const badges = badgeStates(impact, chats, projects);
  const initial = (username || "user")[0].toUpperCase();

  return (
    <>
      <div className="drawer-overlay" onClick={onClose} />
      <div className="impact-drawer">
        <div className="drawer-hero">
          <button className="drawer-back" onClick={onClose}><ChevronLeftIcon size={17} /></button>
          <IsoField />
        </div>
        <div className="profile-card">
          <div className="profile-top">
            <div className="avatar">{initial}</div>
            <div className="profile-handle">@{username || "user"}</div>
            <button className="share-btn" title="Share your impact" onClick={onShare}>
              <ShareIcon size={19} />
            </button>
          </div>
          <div className="profile-grid">
            <div className="trees-block">
              <div className="trees-count">
                {s.trees}<span className="tree-emoji">🌳</span>
              </div>
              <div className="trees-label">Trees planted</div>
              <div className="bar"><i style={{ width: `${Math.max(2, s.treeProgress * 100)}%` }} /></div>
            </div>
            <div className="mini-stats">
              <div className="mini-stat">
                <div className="row">🍃 <span className="n">{s.co2}</span> <span className="lbl">kg of CO2 saved</span></div>
                <div className="bar"><i style={{ width: `${Math.max(2, s.co2Progress * 100)}%` }} /></div>
              </div>
              <div className="mini-stat">
                <div className="row">💧 <span className="n">{s.water}</span> <span className="lbl">L of H2O saved</span></div>
                <div className="bar blue"><i style={{ width: `${Math.max(2, s.waterProgress * 100)}%` }} /></div>
              </div>
              <div className="mini-stat">
                <div className="row">💡 <span className="n">{s.light}</span> <span className="lbl">hr of light saved</span></div>
                <div className="bar orange"><i style={{ width: `${Math.max(2, s.lightProgress * 100)}%` }} /></div>
              </div>
            </div>
          </div>
        </div>

        <div className="drawer-content">
          <div className="drawer-card">
            <h3>Badges <ChevronRightIcon size={16} className="chev" /></h3>
            <div className="badges-row">
              {badges.map((b) => (
                <div className="badge-cell" key={b.key}>
                  <BadgeSeal emoji={b.emoji} locked={!b.unlocked} />
                  <span className="badge-name">{b.name}</span>
                </div>
              ))}
            </div>
          </div>

          <div className="drawer-tabs">
            {[["about", "About"], ["friends", "Friends"], ["rankings", "Rankings"]].map(([k, label]) => (
              <button key={k} className={`drawer-tab ${tab === k ? "active" : ""}`} onClick={() => setTab(k)}>
                {label}
              </button>
            ))}
          </div>

          {tab === "about" && (
            <>
              <div className="drawer-card">
                <div className="about-title">About</div>
                <div className="about-h">The AI Problem</div>
                <p className="body">Our planet is dying because of Big AI.</p>
                <p className="body">Every day, global AI systems waste...</p>
                <ul className="dots">
                  <li>100m+ gallons of water</li>
                  <li>10x as much electricity as all of Greenland</li>
                  <li>7000+ tons of CO2 emissions</li>
                </ul>
                <p className="body">PlantGPT is AI that plants real trees</p>

                <div className="about-h">How does PlantGPT help?</div>
                <p className="body">Efficient ai uses 10% as many resources as big ai.</p>
                <p className="body">This build goes further — the model runs on your own computer. Nothing leaves your machine.</p>
                <div className="compare-row">
                  <div className="compare-card big">
                    {EMOJI_ROWS_BIG.map((r, i) => <div key={i}>{r}</div>)}
                  </div>
                  <div className="compare-card">
                    <div>🪨</div><div>🪨</div><div>⚡</div><div>💧</div><div>💧</div>
                  </div>
                </div>
                <div style={{ display: "flex" }}>
                  <div className="compare-caption" style={{ flex: 1 }}>Big ai models</div>
                  <div className="compare-caption">Efficient ai models</div>
                </div>

                <div className="about-h">Our promise</div>
                <p className="body">Every 100 messages earns you a tree. Make it real for $1 through MrBeast's TeamTrees — $1 = 1 tree planted by the Arbor Day Foundation.</p>
                <p className="body">Your chats never leave this machine, and the app never costs you anything unless you choose to plant.</p>
                <div className="signature">- PlantGPT Team</div>
              </div>
              <button className="policy-card" onClick={() => onOpenExternal("https://teamtrees.org")}>
                <span className="policy-icon"><MapIcon size={20} /></span>
                <span>
                  <div className="t">TeamTrees</div>
                  <div className="d">Donate $1, plant 1 real tree.</div>
                </span>
                <ExtIcon size={16} className="ext" />
              </button>
            </>
          )}

          {tab === "friends" && (
            <div className="drawer-card">
              <h3 style={{ display: "flex", width: "100%" }}>
                My friends
                <button
                  className="add-friend-btn"
                  onClick={() => onToast("Friends need PlantGPT accounts — this build is fully local")}
                >
                  <PlusIcon size={17} />
                </button>
              </h3>
              <div className="friends-empty">
                <div className="ppl">👥</div>
                <p>No friends yet</p>
              </div>
            </div>
          )}

          {tab === "rankings" && (
            <div className="drawer-card">
              <h3>Leaderboard <ChevronRightIcon size={16} className="chev" /></h3>
              <div className="podium">
                <div className="hex-avatar">{initial}</div>
                <div className="handle">@{username || "user"}</div>
                <div className="tree-pill">🌳 {s.trees}</div>
                <div className="podium-block">1st</div>
              </div>
            </div>
          )}
        </div>
      </div>
    </>
  );
}
