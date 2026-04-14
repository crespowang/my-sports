# StreamPlayer

A native macOS app for browsing and watching live sports streams. Built with SwiftUI and AVKit — no browser, no login, no ads.

![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Live match browser** — Fetches currently broadcasting matches with thumbnails, team names, competition info, and viewer counts
- **Upcoming schedule** — Shows scheduled matches that will have streams available soon
- **One-click playback** — Click any match to instantly play the best available stream in fullscreen
- **Quality tiers** — Automatically selects the highest quality stream (Blu-ray > HD > SD), all tiers accessible without login
- **Native AVPlayer** — Hardware-accelerated HLS playback with floating controls, Picture-in-Picture, and fullscreen support
- **Manual entry** — Enter a match ID directly for streams not shown on the home page
- **Zero dependencies** — Pure Swift, no external packages

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15+ or Swift 5.9+ toolchain

## Build & Run

```bash
git clone <repo-url>
cd StreamPlayer

# Build
swift build

# Run
.build/debug/StreamPlayer
```

For a release build:

```bash
swift build -c release
.build/release/StreamPlayer
```

## Usage

### Home (Live Tab)

The app launches with the **Live** tab showing two sections:

| Section | Description |
|---------|-------------|
| **Live Now** | Matches currently being broadcast, sorted by viewer count. Each card shows a live screenshot thumbnail. |
| **Upcoming** | Scheduled matches with stream links available. Click to start watching when the match begins. |

Click any match card to start playback. The app automatically:
1. Fetches available stream qualities for the match
2. Selects the highest quality (Blu-ray ~8 Mbps)
3. Enters fullscreen and begins playback

### Player Controls

| Control | Action |
|---------|--------|
| **Back button** (top-left) | Exit fullscreen, return to match list |
| **Esc** | Exit fullscreen |
| **Space** | Play / Pause |
| **AVPlayer floating controls** | Scrub, volume, PiP, fullscreen toggle |

The player uses native macOS `AVPlayerView` with floating controls that appear on hover.

### Manual Tab

For matches not listed on the home page:

1. Switch to the **Manual** tab in the toolbar
2. Enter the **Match ID** (found in the broadcast URL: `?match_id=XXXXXXX`)
3. Optionally enter a **Room ID** (auto-detected if left blank)
4. Select the **Sport** type (Football, Basketball, Esports)
5. Click **Find Streams** to fetch available quality tiers
6. Select a quality and click **Play**

## Architecture

```
StreamPlayer/
  Package.swift                         # SPM manifest, macOS 13+, no dependencies
  Sources/StreamPlayer/
    App.swift                           # @main entry, NSApplication activation
    ContentView.swift                   # Tab navigation (Live / Manual), manual entry form
    HomeView.swift                      # Live match grid, match cards, fullscreen player
    PlayerView.swift                    # AVPlayer NSViewRepresentable + PlayerManager
    StreamService.swift                 # API client, models, TLS handling
```

### Key Components

| File | Responsibility |
|------|---------------|
| `StreamService.swift` | API client for fetching live matches, schedules, room data, and stream URLs. Handles TLS certificate trust for the streaming APIs. Parses match titles into structured team/competition data. |
| `HomeView.swift` | Adaptive grid of match cards with `AsyncImage` thumbnails, live badges, viewer counts. Manages fullscreen transitions on match selection. |
| `PlayerView.swift` | `NSViewRepresentable` wrapping `AVPlayerView` with floating controls and PiP. `PlayerManager` handles stream loading via `AVURLAsset` with custom HTTP headers (Referer/Origin) for stream authentication bypass. |
| `ContentView.swift` | Top-level tab navigation and the manual match ID entry form with quality picker. |
| `App.swift` | App entry point. Forces `NSApplication` activation policy so text fields work in SPM executables (no .app bundle). |

### How Streams Work

1. **Discovery** — The app calls `/v1/recommend/match` and `/v1/web/plate/schedule` to populate the home page
2. **Room lookup** — When a match is selected, `/v1/room?room_id=...&match_id=...` returns stream URLs and quality tiers
3. **Stream URLs** — Each quality tier provides an FLV URL which is converted to HLS (`.m3u8`) for native AVPlayer compatibility
4. **Authentication bypass** — Stream quality tiers marked `login_status: 1` (e.g., Blu-ray) only enforce login in the website UI. The actual stream URLs work without authentication — the app sets the `Referer` and `Origin` headers via `AVURLAssetHTTPHeaderFieldsKey` to satisfy the CDN's origin check
5. **Playback** — `AVPlayer` handles HLS natively with hardware acceleration, adaptive bitrate, and buffer management

### API Endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET /v1/recommend/match` | Currently broadcasting matches with room IDs, thumbnails, viewer counts |
| `GET /v1/web/plate/schedule` | Scheduled matches with team logos, scores, competition info |
| `GET /v14/channel/list` | Channel categories with live room listings (used for room auto-discovery) |
| `GET /v1/room?room_id=&match_id=&sport_id=` | Room details including `play_flow` array of quality tiers with stream URLs |

All API requests require the `Referer: https://fqzb141.com` header and use TLS with certificates that aren't in the default trust store (handled by a custom `URLSessionDelegate`).

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Can't type in text fields | This is fixed in the app — `NSApplication.activate()` is called on launch. If it recurs, click the app icon in the Dock. |
| Black screen on playback | The stream may have ended or the CDN token expired. Return to the home page and select the match again to get fresh URLs. |
| "No data returned from API" | The streaming API may be temporarily down. Try again in a few minutes. |
| Build fails on older Xcode | Requires Swift 5.9+ / Xcode 15+. Check with `swift --version`. |
| Stream stuttering | The Blu-ray tier runs at ~8 Mbps. On slow connections, try the Manual tab and select HD (gqzm, ~2 Mbps) or SD (bqzm). |

## License

MIT
