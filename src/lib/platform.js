// Small, dependency-free OS detection for tailoring in-app copy (e.g. which
// command restarts Ollama). Reads navigator.platform/userAgent directly so
// it behaves identically inside Tauri's native webview and in a plain
// browser tab (this file has no Tauri import and no other dependency) --
// both report the real host OS through these same navigator fields.
export function isMacPlatform() {
  if (typeof navigator === "undefined") return false;
  const platform = navigator.platform || navigator.userAgentData?.platform || "";
  const ua = navigator.userAgent || "";
  return /Mac/i.test(platform) || /Mac/i.test(ua);
}
