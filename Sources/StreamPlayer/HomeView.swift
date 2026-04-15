import SwiftUI

struct HomeView: View {
    @State private var liveMatches: [LiveMatch] = []
    @State private var schedule: [LiveMatch] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isPlaying = false
    @State private var matchInfo: MatchInfo?
    @State private var loadingMatch: String?

    @StateObject private var playerManager = PlayerManager()
    @State private var isLandscape = false

    var body: some View {
        ZStack {
            if isPlaying, playerManager.player != nil {
                fullscreenPlayer
            } else {
                matchList
            }
        }
        #if os(macOS)
        .frame(minWidth: 800, minHeight: 500)
        #endif
        .task { await loadData() }
    }

    // MARK: - Match List

    private var matchList: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Stream Player")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { Task { await loadData() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
                .foregroundColor(.gray)
                .disabled(isLoading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(white: 0.08))

            if isLoading && liveMatches.isEmpty {
                Spacer()
                ProgressView("Loading matches...")
                    .foregroundColor(.gray)
                Spacer()
            } else if let error = errorMessage, liveMatches.isEmpty && schedule.isEmpty {
                Spacer()
                Text(error).foregroundColor(.red).font(.system(size: 13))
                Spacer()
            } else {
                List {
                    if !liveMatches.isEmpty {
                        Section {
                            matchGrid(liveMatches)
                        } header: {
                            sectionHeader("Live Now", count: liveMatches.count)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    }

                    if !schedule.isEmpty {
                        Section {
                            matchGrid(schedule)
                        } header: {
                            sectionHeader("Upcoming", count: schedule.count)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable {
                    await loadData()
                }
            }
        }
        .background(Color(white: 0.05))
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            if title == "Live Now" {
                Circle().fill(Color.red).frame(width: 8, height: 8)
            }
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Text("\(count)")
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.1))
                .cornerRadius(4)
        }
    }

    private func matchGrid(_ matches: [LiveMatch]) -> some View {
        let minWidth: CGFloat = {
            #if os(iOS)
            return 150
            #else
            return 220
            #endif
        }()
        return LazyVGrid(columns: [
            GridItem(.adaptive(minimum: minWidth, maximum: 300), spacing: 12)
        ], spacing: 12) {
            ForEach(matches) { match in
                MatchCard(match: match, isLoading: loadingMatch == match.id)
                    .onTapGesture { Task { await playMatch(match) } }
            }
        }
    }

    // MARK: - Fullscreen Player

    private var fullscreenPlayer: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if let player = playerManager.player {
                PlayerView(player: player)
                    .ignoresSafeArea()
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
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
                    .padding(16)

                    Spacer()

                    #if os(iOS)
                    Button(action: toggleOrientation) {
                        Image(systemName: isLandscape ? "rectangle.portrait" : "rectangle.landscape.rotate")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(6)
                    }
                    .padding(16)
                    #endif
                }
                Spacer()
            }
        }
        #if os(macOS)
        .onAppear { enterFullscreen() }
        .onDisappear { exitFullscreen() }
        #endif
    }

    // MARK: - Actions

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            async let live = StreamService.shared.fetchLiveMatches()
            async let sched = StreamService.shared.fetchSchedule()
            liveMatches = try await live
            schedule = try await sched
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func playMatch(_ match: LiveMatch) async {
        loadingMatch = match.id
        do {
            let room = try await StreamService.shared.getRoomData(
                roomId: match.roomId, matchId: match.matchId, sportId: match.sportId
            )
            guard let best = room.streams.first else {
                loadingMatch = nil
                return
            }
            matchInfo = room.matchInfo
            playerManager.loadStream(url: best.url)
            isPlaying = true
        } catch {
            errorMessage = error.localizedDescription
        }
        loadingMatch = nil
    }

    private func stopPlaying() {
        #if os(macOS)
        exitFullscreen()
        #endif
        #if os(iOS)
        if isLandscape {
            OrientationHelper.forcePortrait()
            isLandscape = false
        }
        #endif
        playerManager.stop()
        isPlaying = false
    }

    #if os(iOS)
    private func toggleOrientation() {
        if isLandscape {
            OrientationHelper.forcePortrait()
        } else {
            OrientationHelper.forceLandscape()
        }
        isLandscape.toggle()
    }
    #endif

    #if os(macOS)
    private func enterFullscreen() {
        guard let window = NSApplication.shared.windows.first else { return }
        if !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }

    private func exitFullscreen() {
        guard let window = NSApplication.shared.windows.first else { return }
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }
    #endif
}

// MARK: - Match Card

struct MatchCard: View {
    let match: LiveMatch
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack {
                Color(white: 0.12)

                if !match.screenshot.isEmpty, let url = URL(string: match.screenshot) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(16/9, contentMode: .fill)
                        default:
                            sportIcon
                        }
                    }
                } else {
                    sportIcon
                }

                if match.isLive {
                    VStack {
                        HStack {
                            Text("LIVE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .cornerRadius(3)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(8)
                }

                if match.viewers > 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 3) {
                                Image(systemName: "eye.fill")
                                    .font(.system(size: 9))
                                Text(formatViewers(match.viewers))
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(3)
                        }
                    }
                    .padding(8)
                }

                if isLoading {
                    Color.black.opacity(0.5)
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            .clipped()
            .cornerRadius(8, corners: [.topLeft, .topRight])

            // Info
            VStack(alignment: .leading, spacing: 4) {
                if !match.homeName.isEmpty && !match.awayName.isEmpty {
                    HStack(spacing: 0) {
                        teamLogo(match.homeLogo)
                        Text(match.homeName)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("vs")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        Spacer(minLength: 4)
                        Text(match.awayName)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        teamLogo(match.awayLogo)
                    }
                    .foregroundColor(.white)
                } else {
                    Text(match.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }

                if !match.competition.isEmpty {
                    Text(match.competition)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.1))
            .cornerRadius(8, corners: [.bottomLeft, .bottomRight])
        }
        .background(Color(white: 0.1))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }

    @ViewBuilder
    private func teamLogo(_ urlString: String) -> some View {
        if !urlString.isEmpty, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 16, height: 16)
            .padding(.horizontal, 4)
        }
    }

    private var sportIcon: some View {
        Image(systemName: match.sportId == "2" ? "basketball.fill" : "sportscourt.fill")
            .font(.system(size: 30))
            .foregroundColor(Color(white: 0.25))
    }

    private func formatViewers(_ count: Int) -> String {
        if count >= 10000 {
            return String(format: "%.1fw", Double(count) / 10000.0)
        }
        return "\(count)"
    }
}

// MARK: - Corner radius helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCornerSet) -> some View {
        clipShape(RoundedCornerShape(radius: radius, corners: corners))
    }
}

struct RectCornerSet: OptionSet {
    let rawValue: Int
    static let topLeft = RectCornerSet(rawValue: 1 << 0)
    static let topRight = RectCornerSet(rawValue: 1 << 1)
    static let bottomLeft = RectCornerSet(rawValue: 1 << 2)
    static let bottomRight = RectCornerSet(rawValue: 1 << 3)
    static let allCorners: RectCornerSet = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: RectCornerSet

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 { path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false) }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 { path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false) }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 { path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false) }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 { path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false) }
        path.closeSubpath()
        return path
    }
}
