// localStorage persistence. Everything stays on this machine.

const KEYS = {
  settings: "eco.settings",
  chats: "eco.chats",
  projects: "eco.projects",
  impact: "eco.impact",
};

const DEFAULTS = {
  settings: {
    model: "",
    theme: "dark", // dark | light | system
    username: "user",
    studyMode: false,
    webSearch: true, // always-on grounding: model writes a query before each reply
  },
  chats: [],
  projects: [],
  impact: { messages: 0, shares: 0, friends: 0 },
};

function load(key) {
  try {
    const raw = localStorage.getItem(KEYS[key]);
    if (!raw) return structuredClone(DEFAULTS[key]);
    return { ...structuredClone(DEFAULTS[key]), ...JSON.parse(raw) };
  } catch {
    return structuredClone(DEFAULTS[key]);
  }
}

function loadArray(key) {
  try {
    const raw = localStorage.getItem(KEYS[key]);
    if (!raw) return [];
    const v = JSON.parse(raw);
    return Array.isArray(v) ? v : [];
  } catch {
    return [];
  }
}

export const store = {
  loadSettings: () => load("settings"),
  saveSettings: (s) => localStorage.setItem(KEYS.settings, JSON.stringify(s)),
  loadChats: () => loadArray("chats"),
  saveChats: (c) => localStorage.setItem(KEYS.chats, JSON.stringify(c)),
  loadProjects: () => loadArray("projects"),
  saveProjects: (p) => localStorage.setItem(KEYS.projects, JSON.stringify(p)),
  loadImpact: () => load("impact"),
  saveImpact: (i) => localStorage.setItem(KEYS.impact, JSON.stringify(i)),
};

export const uid = () => Math.random().toString(36).slice(2, 10) + Date.now().toString(36);

// Impact math: 100 messages = 1 tree (EcoGPT's own rate); the rest are
// plausible per-message savings vs. big-cloud inference.
export function computeImpact(impact) {
  const m = impact.messages;
  return {
    trees: Math.floor(m / 100),
    treeProgress: (m % 100) / 100,
    co2: +(m * 0.004).toFixed(m < 250 ? 2 : 0),
    water: +(m * 0.02).toFixed(m < 50 ? 2 : 0),
    light: +(m * 0.027).toFixed(m < 40 ? 2 : 0),
    co2Progress: Math.min(1, (m * 0.004) / 10),
    waterProgress: Math.min(1, (m * 0.02) / 50),
    lightProgress: Math.min(1, (m * 0.027) / 60),
  };
}

export function badgeStates(impact, chats, projects) {
  return [
    { key: "first-leaf", name: "First Leaf", emoji: "\u{1F331}", unlocked: impact.messages >= 1 },
    { key: "team-player", name: "Team Player", emoji: "\u{1F46B}", unlocked: projects.length >= 1 },
    { key: "eco-influencer", name: "Eco Influencer", emoji: "\u{1F4E3}", unlocked: impact.shares >= 1 },
    { key: "seed", name: "Seed", emoji: "\u{1F330}", unlocked: impact.messages >= 100 },
  ];
}
