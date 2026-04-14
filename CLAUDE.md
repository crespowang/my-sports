# CLAUDE.md

## About

StreamPlayer is a native multiplatform (macOS + iOS) app for browsing and watching live sports streams from fqzb141.com. Built with SwiftUI and AVKit — no browser, no login, no ads.

## Tech Stack

- **Language:** Swift 6.2 (swift-tools-version: 6.2)
- **UI:** SwiftUI with `#if os(macOS)` / `#if os(iOS)` conditionals for platform-specific code
- **Video:** AVKit — `AVPlayerView` (macOS) / `AVPlayerViewController` (iOS)
- **Networking:** URLSession with custom `URLSessionDelegate` for TLS trust
- **Platforms:** macOS 26+, iOS 26+
- **Build:** Swift Package Manager (CLI) + Xcode project via xcodegen

## Project Structure

```
StreamPlayer/
  Package.swift                      # SPM manifest (swift-tools-version: 6.2)
  project.yml                        # xcodegen spec → generates .xcodeproj
  Support/
    Info-iOS.plist                    # iOS app plist (has CFBundleIdentifier, ATS, orientations)
    Info-macOS.plist                  # macOS app plist (has CFBundleIdentifier, ATS)
  Sources/StreamPlayer/
    App.swift                        # @main entry. macOS: NSApplicationDelegateAdaptor + activate. iOS: no-op.
    ContentView.swift                # Tab nav (Live / Manual). ManualEntryView for match ID entry.
    HomeView.swift                   # Live match grid, MatchCard, fullscreen player, corner radius helpers.
    PlayerView.swift                 # Platform PlayerView (NSViewRepresentable / UIViewControllerRepresentable).
                                     # PlayerManager: AVPlayer lifecycle, AVURLAsset with custom headers.
    StreamService.swift              # API client, models (LiveMatch, MatchInfo, StreamOption, RoomResult),
                                     # TLS delegate, title parsing.
    Assets.xcassets/                  # App icon asset catalog (1024px source, sized variants for macOS)
```

## Build Commands

```bash
# macOS via SPM (fast iteration)
swift build                          # Debug build
swift build -c release               # Release build
.build/debug/StreamPlayer            # Run debug
.build/release/StreamPlayer          # Run release

# Regenerate Xcode project (after changing project.yml)
xcodegen generate

# iOS — must use Xcode
# Open StreamPlayer.xcodeproj, select StreamPlayer-iOS scheme, run on device/simulator
```

## Desktop .app Bundle

A macOS .app bundle lives at `~/Desktop/StreamPlayer.app`. After rebuilding:
```bash
swift build -c release
cp .build/release/StreamPlayer ~/Desktop/StreamPlayer.app/Contents/MacOS/StreamPlayer
```

## Streaming Architecture

### API Base
All APIs live at `https://apc.j8w1d1r1p4g4q6t.cc`. All requests require `Referer: https://fqzb141.com` header. TLS certs are not in the default trust store — handled by `TLSDelegate` with `rejectUnauthorized: false` equivalent.

### Key API Endpoints

| Endpoint | Purpose | Used in |
|----------|---------|---------|
| `GET /v1/recommend/match` | Live broadcasting matches (room IDs, thumbnails, viewers) | `fetchLiveMatches()` |
| `GET /v1/web/plate/schedule` | Scheduled matches (team logos, scores, competition) | `fetchSchedule()` |
| `GET /v14/channel/list` | Channel categories with live room listings | `findRooms()` |
| `GET /v1/room?room_id=&match_id=&sport_id=` | Room details with `play_flow` quality tiers | `getRoomData()` |

### Stream Quality Tiers

Returned in `play_flow` array from the room API, sorted by `sort` descending:

| Code ID | Name | Bitrate | login_status |
|---------|------|---------|--------------|
| `lgzm` | 蓝光 (Blu-ray) | ~8 Mbps | 1 (UI-only gate, stream URL works without auth) |
| `gqzm` | 高清 (HD) | ~2 Mbps | 0 |
| `bqzm` | 标清 (SD) | ~0.8 Mbps | 0 |

### Stream URL Handling

1. API returns FLV URLs → app converts `.flv` → `.m3u8` for HLS
2. `AVURLAsset` created with `"AVURLAssetHTTPHeaderFieldsKey"` option to inject `Referer` and `Origin` headers
3. This bypasses the CDN's origin check without needing a proxy server
4. On iOS, `AVAudioSession` is set to `.playback` mode for background audio

## Platform Differences

| Concern | macOS | iOS |
|---------|-------|-----|
| Player view | `NSViewRepresentable` + `AVPlayerView` (floating controls, PiP) | `UIViewControllerRepresentable` + `AVPlayerViewController` (native fullscreen) |
| App activation | `NSApplication.setActivationPolicy(.regular)` + `activate()` needed for SPM executables | Not needed |
| Fullscreen | `window.toggleFullScreen()` on play/stop | Handled by `AVPlayerViewController.entersFullScreenWhenPlaybackBegins` |
| Window sizing | `.defaultSize(width: 960, height: 640)` | N/A |
| Grid columns | `minimum: 220` | `minimum: 150` |
| Button style | `.buttonStyle(.plain)` on icon buttons | Default (no `.plain` needed) |
| Keyboard | `.keyboardShortcut(.return, modifiers: [])` | `.keyboardShortcut(.return)` |
| Number input | Default text field | `.keyboardType(.numberPad)` |
| Color scheme | System | Forced `.preferredColorScheme(.dark)` |

## Swift 6 Concurrency

- `StreamService` marked `@unchecked Sendable` (singleton with `URLSession`)
- `PlayerManager` marked `@MainActor` (publishes UI state)
- `TLSDelegate` marked `final class ... @unchecked Sendable`
- NotificationCenter observer dispatches back to `@MainActor` via `Task`

## Key Design Decisions

- **No proxy server:** `AVURLAssetHTTPHeaderFieldsKey` (private but stable API) injects HTTP headers directly, avoiding the complexity of a local proxy
- **Single source set:** All Swift files compile for both platforms using `#if os()` — no separate targets/folders
- **xcodegen for .xcodeproj:** The Xcode project is generated from `project.yml`, not hand-maintained. Run `xcodegen generate` after changes.
- **App icon:** Single 1024x1024 source resized to all required Mac sizes via `sips`. iOS uses the universal 1024px slot.

## Important Notes

- **NEVER auto-commit or auto-push** — only when explicitly requested
- The `play_flow[].login_status` flag is only enforced in the website's JavaScript UI — all stream URLs work without authentication
- Stream URLs contain time-limited tokens (`txSecret`, `txTime`) — they expire and must be re-fetched from the room API
- The room API uses `room_id=888888888` as a default/catch-all room for matches without a dedicated broadcaster
