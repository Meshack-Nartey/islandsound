// content-boomplay.js -- reports Boomplay's now-playing state to
// IslandSound and handles PLAY_REQUEST handoffs (Sections 5.4-5.5).
//
// Boomplay's web player markup is not officially documented and may change
// between releases. The selectors below cover the player bar's track-title
// and artist elements as well as a generic `<audio>` element; if Boomplay
// updates its UI, update SELECTORS below to match.

const SOURCE = "boomplay";
const REPORT_INTERVAL_MS = 1000;

const SELECTORS = {
  title: [".player-bar .music-name", ".player-content .song-name", ".now-playing .title"],
  artist: [".player-bar .singer-name", ".player-content .singer", ".now-playing .artist"],
};

function queryFirst(selectors) {
  for (const selector of selectors) {
    const el = document.querySelector(selector);
    if (el && el.textContent && el.textContent.trim()) return el;
  }
  return null;
}

function readNowPlaying() {
  const audio = document.querySelector("audio");
  const titleEl = queryFirst(SELECTORS.title);
  const artistEl = queryFirst(SELECTORS.artist);

  if (!audio || !titleEl) return null;

  const title = titleEl.textContent.trim();
  if (!title) return null;

  return {
    type: "NOW_PLAYING",
    title,
    artist: artistEl ? artistEl.textContent.trim() : "",
    position: audio.currentTime || 0,
    source: SOURCE,
  };
}

let lastReport = null;

setInterval(() => {
  const info = readNowPlaying();
  if (!info) return;

  const changed =
    !lastReport ||
    lastReport.title !== info.title ||
    lastReport.artist !== info.artist ||
    Math.abs(lastReport.position - info.position) > 0.75;

  if (changed) {
    lastReport = info;
    chrome.runtime.sendMessage(info);
  }
}, REPORT_INTERVAL_MS);

// Handles a handoff request from IslandSound: resume the same track if
// it's already loaded, otherwise search for it.
chrome.runtime.onMessage.addListener((message) => {
  if (message.type !== "PLAY_REQUEST" || message.source !== SOURCE) return;

  const current = readNowPlaying();
  const matches =
    current &&
    current.title.toLowerCase() === (message.title || "").toLowerCase() &&
    current.artist.toLowerCase() === (message.artist || "").toLowerCase();

  const audio = document.querySelector("audio");

  if (matches && audio) {
    if (typeof message.position === "number") {
      audio.currentTime = message.position;
    }
    audio.play();
    return;
  }

  const query = `${message.title || ""} ${message.artist || ""}`.trim();
  if (query) {
    location.href = `https://www.boomplay.com/search/${encodeURIComponent(query)}`;
  }
});
