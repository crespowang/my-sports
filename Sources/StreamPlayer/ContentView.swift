import SwiftUI

enum AppTab {
    case home
    case manual
}

struct ContentView: View {
    @State private var currentTab: AppTab = .home

    var body: some View {
        ZStack {
            Color(white: 0.05).ignoresSafeArea()

            switch currentTab {
            case .home:
                HomeView()
            case .manual:
                ManualEntryView(onBack: { currentTab = .home })
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                Picker("", selection: $currentTab) {
                    Text("Live").tag(AppTab.home)
                    Text("Manual").tag(AppTab.manual)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
        }
    }
}

// MARK: - Manual Entry View (original setup)

struct ManualEntryView: View {
    let onBack: () -> Void

    @State private var matchId = ""
    @State private var roomId = ""
    @State private var sportId = "1"
    @State private var streams: [StreamOption] = []
    @State private var selectedStream: StreamOption?
    @State private var matchInfo: MatchInfo?
    @State private var isLoading = false
    @State private var errorMessage: String?

    @StateObject private var playerManager = PlayerManager()
    @State private var isPlaying = false

    var body: some View {
        ZStack {
            if isPlaying, playerManager.player != nil {
                playerView
            } else {
                setupView
            }
        }
    }

    private var setupView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Manual Stream")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                Text("Enter a match ID to start watching")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Match ID").font(.system(size: 12, weight: .medium)).foregroundColor(.gray)
                    TextField("e.g. 4517582", text: $matchId)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await fetchStreams() } }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Room ID (optional)").font(.system(size: 12, weight: .medium)).foregroundColor(.gray)
                        TextField("Auto-detect", text: $roomId)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sport").font(.system(size: 12, weight: .medium)).foregroundColor(.gray)
                        Picker("", selection: $sportId) {
                            Text("Football").tag("1")
                            Text("Basketball").tag("2")
                            Text("Esports").tag("3")
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }
                }

                if !streams.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Quality").font(.system(size: 12, weight: .medium)).foregroundColor(.gray)
                        Picker("", selection: $selectedStream) {
                            ForEach(streams) { s in
                                Text(s.name).tag(Optional(s))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                }

                if let info = matchInfo {
                    HStack {
                        Spacer()
                        Text(info.homeName).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        Text("\(info.homeScore)").font(.system(size: 20, weight: .bold)).foregroundColor(.cyan)
                        Text("-").foregroundColor(.gray)
                        Text("\(info.awayScore)").font(.system(size: 20, weight: .bold)).foregroundColor(.cyan)
                        Text(info.awayName).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 12)).foregroundColor(.red)
                        .padding(8).frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.1)).cornerRadius(6)
                }

                HStack(spacing: 12) {
                    Button(action: { Task { await fetchStreams() } }) {
                        HStack {
                            if isLoading { ProgressView().scaleEffect(0.7).frame(width: 16, height: 16) }
                            Text(streams.isEmpty ? "Find Streams" : "Refresh")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(matchId.isEmpty || isLoading)
                    .controlSize(.large)

                    if selectedStream != nil {
                        Button(action: play) {
                            Text("Play").frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .keyboardShortcut(.return, modifiers: [])
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: 480)
            Spacer()
        }
    }

    private var playerView: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let player = playerManager.player {
                PlayerView(player: player).ignoresSafeArea()
            }
            VStack {
                HStack {
                    Button(action: stopPlaying) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                    Spacer()
                }
                Spacer()
            }
        }
    }

    private func fetchStreams() async {
        guard !matchId.isEmpty else { return }
        isLoading = true; errorMessage = nil
        streams = []; selectedStream = nil; matchInfo = nil

        do {
            var rid = roomId
            if rid.isEmpty {
                let rooms = try await StreamService.shared.findRooms(matchId: matchId, sportId: sportId)
                guard let first = rooms.first else { throw StreamError.noRooms }
                rid = first; roomId = rid
            }
            let result = try await StreamService.shared.getRoomData(roomId: rid, matchId: matchId, sportId: sportId)
            streams = result.streams; matchInfo = result.matchInfo; selectedStream = result.streams.first
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    private func play() {
        guard let stream = selectedStream else { return }
        playerManager.loadStream(url: stream.url)
        isPlaying = true
        // Enter fullscreen
        if let window = NSApplication.shared.windows.first, !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }

    private func stopPlaying() {
        if let window = NSApplication.shared.windows.first, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        playerManager.stop()
        isPlaying = false
    }
}
