# IslandSound

A native macOS Dynamic Island-style music companion with five signature features:

1. **Mood-Based Dynamic Theming** — the island's glow colour and pulse speed react to the BPM, energy and warmth of whatever's playing, computed on-device via FFT.
2. **Cross-App Listening Continuity** — hand off playback between Apple Music, Spotify, Boomplay and YouTube Music, preserving the track and position.
3. **Collaborative Listening Rooms** — host or join a room and stay in sync with friends via a small Spring Boot/STOMP backend.
4. **Offline Time-Synced Karaoke Lyrics** — synced lyrics fetched from [LRCLIB](https://lrclib.net), cached locally for offline playback.
5. **Voice-Controlled Island** — "Hey Island, ..." wake-phrase commands (skip, pause, volume, "who sings this?", etc.) via on-device speech recognition and ShazamKit.

## Repository layout

```
IslandSound/          Swift Package Manager macOS app (the main product)
islandsound-server/   Spring Boot backend for collaborative listening rooms
BrowserExtension/      Manifest V3 extension bridging Boomplay / YouTube Music tabs
```

---

## 1. Building & running the macOS app

The app is structured as a Swift Package (no `.xcodeproj`) so it builds entirely from the command line with Swift 5.10+ / Xcode 15.3+.

```bash
cd IslandSound
swift build              # debug build
swift test               # run the unit test suite (see "Testing" below)
```

### Running

`IslandSound` is a menu-bar/accessory app (`LSUIElement = true`, no Dock icon, no main window — it lives in the notch). It needs a proper `.app` bundle so macOS grants it microphone/speech permissions correctly. Use the provided script:

```bash
Scripts/build_app.sh release   # or `debug`
open .build/IslandSound.app
```

This compiles the executable, then wraps it with `Resources/Info.plist` into `.build/IslandSound.app/Contents/{MacOS,Resources}`.

On first launch macOS will prompt for:
- **Microphone access** — used for mood analysis (FFT on ambient audio) and ShazamKit "who sings this?" matching.
- **Speech Recognition** — used for the always-on "Hey Island" wake phrase.
- **Automation (Apple Events)** — used to read/control Apple Music and Spotify.

### Architectural deviations from the build spec

These are intentional adjustments made to keep the project buildable as a plain SPM package with zero third-party dependencies:

- **`ObservableObject` + `@Published`** is used throughout instead of the newer `@Observable` macro, for broader toolchain compatibility with SPM command-line builds.
- **Minimum deployment target is macOS 14**, not 13, because `MoodEngine`/`VoiceEngine` rely on `AVAudioEngine` input-tap APIs and `SHSession` streaming APIs that are most reliable on 14+.
- **`MoodEngine` and `VoiceEngine` analyse the default *input* device** (`AVAudioEngine().inputNode`, i.e. the microphone), not system audio output. macOS has no public, sandboxed-friendly API for tapping arbitrary app output (that requires a system audio capture extension/driver). In practice this means mood theming and "who sings this?" work best when music is audible in the room rather than only through headphones.
- **`CollabEngine` speaks STOMP-over-WebSocket by hand** (`URLSessionWebSocketTask` + manually-framed STOMP frames) rather than via a STOMP client library, since SPM has no first-party one and the protocol is simple enough to frame directly.
- **`BrowserBridgeServer` is a from-scratch RFC 6455 WebSocket server** built on `Network` + `CryptoKit`, again to avoid third-party dependencies for a ~50-line handshake.

---

## 2. Collaborative listening backend (`islandsound-server`)

A small Spring Boot 3 app that brokers room creation and STOMP message relay for Collaborative Listening Rooms (Feature 3). Requires Java 21 and Maven.

```bash
cd islandsound-server
mvn test                 # unit tests (RoomService)
mvn spring-boot:run       # run on http://localhost:8080
```

Or build and run the jar directly:

```bash
mvn package -DskipTests
java -jar target/islandsound-server-1.0.0.jar
```

### Protocol contract (Swift `CollabEngine` <-> server)

- `POST /api/rooms` -> `{ "code": "ABC123" }` — host creates a room and gets back a 6-character code (unambiguous alphabet: `23456789ABCDEFGHJKMNPQRSTUVWXYZ`).
- STOMP over WebSocket at `ws://localhost:8080/ws` (raw endpoint, no SockJS).
- Clients `SUBSCRIBE /topic/room/{code}` to receive roster updates, sync ticks and reactions.
- `SEND /app/room/{code}/join` / `/leave` with a `{name, avatar}` `Participant` -> broadcasts `{"type":"PARTICIPANT_UPDATE", "participants": [...]}`.
- Host `SEND /app/room/{code}/sync` every 3s with a `SyncMessage` (`trackId`, `trackTitle`, `artist`, `position`, `isPlaying`, `timestamp`) -> rebroadcast to all subscribers (guests apply it, the host ignores its own echo).
- Any participant `SEND /app/room/{code}/reaction` with `{"type":"REACTION","emoji":..., "from":...}` -> rebroadcast to all subscribers.
- Rooms with no participants are dropped immediately; rooms idle for 6 hours are evicted by a scheduled sweep.

By default the Swift app talks to `http://localhost:8080`. Override with the `ISLANDSOUND_SERVER_URL` environment variable (the WebSocket URL is derived by swapping the scheme to `ws`/`wss` and appending `/ws`):

```bash
ISLANDSOUND_SERVER_URL=https://your-server.example.com open .build/IslandSound.app
```

---

## 3. Browser bridge extension (`BrowserExtension`)

A Manifest V3 extension that reports now-playing info from Boomplay and YouTube Music web players to IslandSound, and lets IslandSound hand playback off *to* those tabs (Feature 2).

### How it works

- `background.js` is a service worker that maintains a WebSocket connection to `ws://localhost:47832`, which `BrowserBridgeServer` inside IslandSound listens on. It auto-reconnects every 3 seconds if the app isn't running yet.
- `content-youtube-music.js` / `content-boomplay.js` poll the page's `<video>`/`<audio>` element and the player bar's title/artist text once per second, and report `{title, artist, position, source}` whenever it changes.
- When IslandSound sends a `PLAY_REQUEST` (cross-app handoff), the background worker relays it to the matching site's tabs; the content script resumes the same track at the given position if it's already loaded, or runs a search for it otherwise.

### Installing (Chrome / Edge / Brave / Arc)

1. Open `chrome://extensions`.
2. Enable **Developer mode** (top right).
3. Click **Load unpacked** and select the `BrowserExtension/` directory.
4. With IslandSound running, open YouTube Music or Boomplay and start playing something — the island should pick up the track.

> **Note on Boomplay selectors**: Boomplay's web player markup isn't officially documented and may change between releases. If now-playing detection stops working, update the CSS selectors in `SELECTORS` at the top of `content-boomplay.js` to match the current DOM (inspect the player bar's title/artist elements).

> The manifest intentionally omits `icons` — they're optional for unpacked/developer-mode extensions and aren't required for functionality.

---

## Testing

| Suite | Command | Covers |
|---|---|---|
| Swift unit tests | `cd IslandSound && swift test` | `MoodTheme` BPM/energy/warmth → theme mapping, `LRCParser` (well-formed, malformed, metadata-tag, fraction-width edge cases), `LRCLIBClient` (live integration test against lrclib.net, skipped if offline), `LyricsCache` (CoreData round-trip via an in-memory store), `AudioAnalyzer` (FFT-based energy/warmth on synthetic tones), `AppleScriptBridge.escape` (quote/backslash/injection safety), `VoiceCommand.match` (wake-phrase command parsing & precedence) |
| Backend unit tests | `cd islandsound-server && mvn test` | `RoomService` room-code generation, uniqueness, and cleanup |

The Swift test target uses `@testable import IslandSound` and lives in `IslandSound/Tests/IslandSoundTests`.
