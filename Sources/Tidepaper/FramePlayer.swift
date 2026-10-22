import AppKit

/// Plays an `AnimatedImage` into any number of layers, one per display.
///
/// Animations that fit in `memoryBudget` once decoded are handed to Core Animation as a
/// keyframe animation: it decodes every frame once, then plays them without using our CPU.
/// Larger ones are streamed: each frame is handed over when it is due and decoded then.
@MainActor
final class FramePlayer {
    static let memoryBudget = 300 * 1024 * 1024
    private static let animationKey = "frames"

    private var layers: [CALayer] = []
    /// What layers show when no keyframe animation runs: the only frame, or the latest streamed one.
    private var currentFrame: CGImage?
    private var animation: CAKeyframeAnimation?
    /// Bumped on every `play`/`stop` so a load finishing late for a replaced image is dropped.
    private var generation = 0

    private var streamedImage: AnimatedImage?
    private var streamIndex = 0
    private var streamTask: Task<Void, Never>?

    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            layers.forEach(updateTiming(of:))
            updateStreaming()
        }
    }

    func attach(_ layer: CALayer) {
        layers.append(layer)
        apply(to: layer)
    }

    func detach(_ layer: CALayer) {
        layers.removeAll { $0 === layer }
        layer.removeAnimation(forKey: Self.animationKey)
        layer.contents = nil
    }

    func play(_ image: AnimatedImage) {
        stop()

        if image.frameCount > 1 && image.decodedByteCount > Self.memoryBudget {
            streamedImage = image
            updateStreaming()
            return
        }

        let generation = self.generation
        Task {
            let frames = await Task.detached(priority: .userInitiated) { image.allFrames() }.value
            guard self.generation == generation, let first = frames.first else { return }
            currentFrame = first.image
            if frames.count > 1 { animation = Self.makeAnimation(frames) }
            layers.forEach(apply(to:))
        }
    }

    func stop() {
        generation += 1
        streamedImage = nil
        streamIndex = 0
        updateStreaming()
        animation = nil
        currentFrame = nil
        layers.forEach(apply(to:))
    }

    // MARK: Keyframe playback

    private func apply(to layer: CALayer) {
        layer.removeAnimation(forKey: Self.animationKey)
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        layer.contents = currentFrame
        if let animation { layer.add(animation, forKey: Self.animationKey) }
        updateTiming(of: layer)
    }

    /// Freezes or resumes the layer's clock, keeping its place in the animation (Apple QA1673).
    private func updateTiming(of layer: CALayer) {
        let isFrozen = layer.speed == 0
        if isPaused && !isFrozen {
            let now = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = now
        } else if !isPaused && isFrozen {
            let pausedAt = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        }
    }

    private static func makeAnimation(_ frames: [AnimatedImage.Frame]) -> CAKeyframeAnimation {
        let duration = frames.reduce(0) { $0 + $1.delay }
        // Discrete mode wants one more key time than values: where each frame starts, then 1.
        var keyTimes: [NSNumber] = [0]
        var elapsed: TimeInterval = 0
        for frame in frames.dropLast() {
            elapsed += frame.delay
            keyTimes.append(NSNumber(value: elapsed / duration))
        }
        keyTimes.append(1)

        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames.map(\.image)
        animation.keyTimes = keyTimes
        animation.calculationMode = .discrete
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }

    // MARK: Streaming playback

    /// Runs the stream while there is a streamed image and playback isn't paused.
    private func updateStreaming() {
        streamTask?.cancel()
        streamTask = nil
        guard let image = streamedImage, !isPaused else { return }
        streamTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let index = self.streamIndex
                if let frame = image.frame(at: index) {
                    self.currentFrame = frame
                    for layer in self.layers { layer.contents = frame }
                }
                self.streamIndex = (index + 1) % image.frameCount
                try? await Task.sleep(for: .seconds(image.delays[index]))
            }
        }
    }
}
