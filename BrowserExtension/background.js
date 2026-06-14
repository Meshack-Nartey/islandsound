// background.js -- bridges this extension to the IslandSound macOS app.
//
// IslandSound runs a local WebSocket server (BrowserBridgeServer) at
// ws://localhost:47832. Content scripts report now-playing state via
// chrome.runtime.sendMessage({type: "NOW_PLAYING", ...}); this worker
// forwards that as {title, artist, position, source} JSON, matching the
// Swift `BrowserBridgeMessage` struct.
//
// IslandSound may also send {type: "PLAY_REQUEST", title, artist, position,
// source} to hand off playback to a browser tab (Section 5.5). `source` on
// PLAY_REQUEST is the target's MusicSource raw value: "youtubeMusic" or
// "boomplay" -- NOT the "youtube"/"boomplay" strings used for NOW_PLAYING.

const BRIDGE_URL = "ws://localhost:47832";
const RECONNECT_DELAY_MS = 3000;

let socket = null;

function connect() {
  socket = new WebSocket(BRIDGE_URL);

  socket.addEventListener("open", () => {
    console.log("[IslandSound Bridge] connected to", BRIDGE_URL);
  });

  socket.addEventListener("message", (event) => {
    let message;
    try {
      message = JSON.parse(event.data);
    } catch (error) {
      console.error("[IslandSound Bridge] failed to parse message", error);
      return;
    }
    if (message.type === "PLAY_REQUEST") {
      relayPlayRequest(message);
    }
  });

  socket.addEventListener("close", scheduleReconnect);
  socket.addEventListener("error", () => socket && socket.close());
}

function scheduleReconnect() {
  socket = null;
  setTimeout(connect, RECONNECT_DELAY_MS);
}

function send(payload) {
  if (socket && socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(payload));
  }
}

/** Relays a PLAY_REQUEST from IslandSound to the matching site's tabs. */
async function relayPlayRequest(message) {
  const pattern =
    message.source === "youtubeMusic"
      ? "*://music.youtube.com/*"
      : "*://www.boomplay.com/*";

  const tabs = await chrome.tabs.query({ url: pattern });
  for (const tab of tabs) {
    if (tab.id !== undefined) {
      chrome.tabs.sendMessage(tab.id, message);
    }
  }
}

// Now-playing reports from content scripts.
chrome.runtime.onMessage.addListener((message) => {
  if (message.type === "NOW_PLAYING") {
    send({
      title: message.title,
      artist: message.artist,
      position: message.position,
      source: message.source,
    });
  }
});

connect();
