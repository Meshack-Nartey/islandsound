// content-youtube-music.js -- reports YouTube Music's now-playing state to
// IslandSound and handles PLAY_REQUEST handoffs (Sections 5.4-5.5).

// "youtube" matches PlaybackEngine.handleBrowserBridgeMessage's check for
// incoming NOW_PLAYING; "youtubeMusic" is MusicSource.youtubeMusic.rawValue,
// used by IslandSound when it sends us a PLAY_REQUEST.
const NOW_PLAYING_SOURCE = "youtube";
const PLAY_REQUEST_SOURCE = "youtubeMusic";
const REPORT_INTERVAL_MS = 1000;

function readNowPlaying() {
  const video = document.querySelector("video");
  const titleEl = document.querySelector(".title.ytmusic-player-bar");
  const artistEl = document.querySelector(".byline.ytmusic-player-bar");

  if (!video || !titleEl) return null;

  const title = titleEl.textContent ? titleEl.textContent.trim() : "";
  const byline = artistEl && artistEl.textContent ? artistEl.textContent : "";
  const artist = byline.split("•")[0].trim();

  if (!title) return null;

  return {
    type: "NOW_PLAYING",
    title,
    artist,
    position: video.currentTime || 0,
    source: NOW_PLAYING_SOURCE,
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
  if (message.type !== "PLAY_REQUEST" || message.source !== PLAY_REQUEST_SOURCE) return;

  const current = readNowPlaying();
  const matches =
    current &&
    current.title.toLowerCase() === (message.title || "").toLowerCase() &&
    current.artist.toLowerCase() === (message.artist || "").toLowerCase();

  const video = document.querySelector("video");

  if (matches && video) {
    if (typeof message.position === "number") {
      video.currentTime = message.position;
    }
    video.play();
    return;
  }

  const query = `${message.title || ""} ${message.artist || ""}`.trim();
  if (query) {
    location.href = `https://music.youtube.com/search?q=${encodeURIComponent(query)}`;
  }
});
