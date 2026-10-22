import AVFoundation

/// Loops a movie, muted, in any number of player layers, one per display.
/// The system's hardware decoder does the work, so even 4K video costs little CPU.
@MainActor
final class VideoPlayer {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var layers: [AVPlayerLayer] = []

    var isPaused = false {
        didSet { updateRate() }
    }

    init() {
        player.isMuted = true
        // A wallpaper must never keep the display awake.
        player.preventsDisplaySleepDuringVideoPlayback = false
    }

    func attach(_ layer: AVPlayerLayer) {
        layers.append(layer)
        layer.player = looper == nil ? nil : player
    }

    func detach(_ layer: AVPlayerLayer) {
        layers.removeAll { $0 === layer }
        layer.player = nil
    }

    func play(_ asset: AVAsset) {
        stop()
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
        for layer in layers { layer.player = player }
        updateRate()
    }

    func stop() {
        looper?.disableLooping()
        looper = nil
        player.pause()
        player.removeAllItems()
        for layer in layers { layer.player = nil }
    }

    private func updateRate() {
        if looper != nil && !isPaused {
            player.play()
        } else {
            player.pause()
        }
    }
}
