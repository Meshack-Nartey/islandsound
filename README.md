# IslandSound

A native macOS Dynamic-Island-style music companion: mood-reactive theming, cross-app handoff, listen-together rooms, and on-device "Hey Island" voice control.

**[Website](website/index.html)** · **[Download for macOS (.zip)](dist/IslandSound-macOS.zip)** · **[Releases](https://github.com/Meshack-Nartey/islandsound/releases)** · **[Source](https://github.com/Meshack-Nartey/islandsound)**

## Features

- **Mood-Based Dynamic Theming** — glow colour and pulse react to the music's BPM, energy and warmth, computed on-device via FFT.
- **Cross-App Listening Continuity** — hand off playback between Apple Music, Spotify, Boomplay and YouTube Music.
- **Listen Together** — host or join a room and stay in sync with friends.
- **"Hey Island" Voice Control** — on-device wake-phrase commands, plus ShazamKit song ID.

## Repository layout

| Path | What it is |
|---|---|
| `IslandSound/` | Swift Package Manager macOS app (the main product) |
| `islandsound-server/` | Spring Boot backend for Listen Together rooms |
| `BrowserExtension/` | Browser extension bridging Boomplay / YouTube Music |
| `website/` | Promotional landing page |
| `dist/` | Prebuilt `.app`, zipped for download |

## Build & run

```bash
cd IslandSound
swift build && swift test
./Scripts/build_app.sh release   # -> .build/IslandSound.app
open .build/IslandSound.app
```

On first launch, grant Microphone, Speech Recognition and Automation access — these power mood detection, "Hey Island", and Apple Music/Spotify control.

For the collab backend and browser extension, see [islandsound-server/](islandsound-server/) and [BrowserExtension/](BrowserExtension/). For architecture notes, the room protocol, and the test matrix, see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
