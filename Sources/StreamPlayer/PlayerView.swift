import AVFoundation
import AVKit
import SwiftUI

// MARK: - Platform Player Views

#if os(macOS)
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}
#else
struct PlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.entersFullScreenWhenPlaybackBegins = true
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        vc.player = player
    }
}
#endif

// MARK: - Player Manager (shared)

@MainActor
class PlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var volume: Float = 1.0
    @Published var isMuted = false
    @Published var errorMessage: String?

    private let siteOrigin = "https://fqzb141.com"
    private var timeObserver: Any?

    func loadStream(url: String) {
        stop()
        errorMessage = nil

        guard let streamUrl = URL(string: url) else {
            errorMessage = "Invalid stream URL"
            return
        }

        let headers: [String: String] = [
            "Referer": siteOrigin,
            "Origin": siteOrigin,
        ]
        let asset = AVURLAsset(
            url: streamUrl,
            options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
        )

        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.volume = volume
        newPlayer.isMuted = isMuted

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item, queue: .main
        ) { [weak self] notification in
            let msg = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
            Task { @MainActor in self?.errorMessage = msg }
        }

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        self.player = newPlayer
        newPlayer.play()
        isPlaying = true
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    func stop() {
        player?.pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player = nil
        isPlaying = false
    }

    func setVolume(_ vol: Float) {
        volume = vol
        player?.volume = vol
    }

    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    func jumpToLive() {
        guard let player, let item = player.currentItem else { return }
        if let lastRange = item.seekableTimeRanges.last?.timeRangeValue {
            player.seek(to: CMTimeAdd(lastRange.start, lastRange.duration))
        }
    }
}
