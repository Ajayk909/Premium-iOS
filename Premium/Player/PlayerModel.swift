import SwiftUI
import AVKit
import MediaPlayer
import Observation

/// One player for the whole app: the watch page, the mini player, Picture in Picture,
/// the lock screen and background audio all share it.
@Observable
final class PlayerModel: NSObject {
    static let shared = PlayerModel()

    var current: Video?
    var details: VideoDetails?
    var expanded = false
    var isPlaying = false
    var time: Double = 0
    var duration: Double = 0
    var loading = false
    var error: String?
    var queue: [Video] = []
    var audioOnly = false
    var speed: Float = 1
    var sleepAt: Date?
    var sleepAtEnd = false
    var segments: [SkipSegment] = []
    var toast: String?
    var pipActive = false

    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var pip: AVPictureInPictureController?
    @ObservationIgnored private weak var mainLayer: AVPlayerLayer?
    @ObservationIgnored private var detachedLayers: [AVPlayerLayer] = []
    @ObservationIgnored private var lastSkip: Double = -10
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private var pendingWatch: Double = 0

    override init() {
        super.init()
        speed = Float(AppSettings.shared.d.speed)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        player.allowsExternalPlayback = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            self?.tick(t)
        }
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(itemEnded), name: .AVPlayerItemDidPlayToEndTime, object: nil)
        nc.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        setupRemoteCommands()
    }

    // MARK: Loading

    func play(_ v: Video, expand: Bool = true) {
        if current?.id == v.id {
            if expand { withAnimation(Motion.spring) { expanded = true } }
            return
        }
        saveProgress()
        current = v
        details = nil
        segments = []
        error = nil
        time = 0
        duration = Double(v.durationSeconds ?? 0)
        if expand { withAnimation(Motion.spring) { expanded = true } }
        Library.shared.addHistory(v)
        load(v, resume: true)
    }

    func reload() {
        guard let v = current else { return }
        let at = time
        load(v, resume: false, seekTo: at)
    }

    private func load(_ v: Video, resume: Bool, seekTo: Double? = nil) {
        loadTask?.cancel()
        loading = true
        player.replaceCurrentItem(with: nil)
        let audioOnly = self.audioOnly
        let maxHeight = AppSettings.shared.d.dataSaver ? 480 : 1080
        let cats = AppSettings.shared.d.sponsorCategories
        loadTask = Task { @MainActor in
            async let info = try? InnerTube.shared.details(v.id)
            async let segs = SponsorBlock.segments(v.id, categories: cats)
            do {
                let item = try await Streams.item(for: v.id, audioOnly: audioOnly, maxHeight: maxHeight)
                guard !Task.isCancelled, self.current?.id == v.id else { return }
                self.player.replaceCurrentItem(with: item)
                var start = seekTo ?? 0
                if resume {
                    let saved = Library.shared.progress(v.id)
                    let total = Double(v.durationSeconds ?? 0)
                    if saved > 10 && (total == 0 || saved < total - 15) { start = saved }
                }
                if start > 1 { await self.player.seek(to: CMTime(seconds: start, preferredTimescale: 600)) }
                self.player.playImmediately(atRate: self.speed)
                self.isPlaying = true
            } catch {
                if !Task.isCancelled { self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't play this video." }
            }
            self.loading = false
            if let d = await info, self.current?.id == v.id {
                self.details = d
                var merged = v
                if merged.title.isEmpty { merged.title = d.video.title }
                if merged.channel.isEmpty { merged.channel = d.channel?.name ?? "" }
                merged.channelId = merged.channelId ?? d.channel?.id
                merged.channelAvatar = merged.channelAvatar ?? d.channel?.avatar
                merged.views = merged.views ?? d.views
                self.current = merged
                Library.shared.updateVideo(merged)
                if let c = d.channel { Library.shared.updateChannel(c) }
            }
            let s = await segs
            if self.current?.id == v.id { self.segments = s }
            self.updateNowPlaying()
        }
    }

    // MARK: Controls

    func toggle() { isPlaying ? pause() : resume() }

    func pause() {
        player.pause()
        isPlaying = false
        saveProgress()
        updateNowPlaying()
    }

    func resume() {
        player.playImmediately(atRate: speed)
        isPlaying = true
        updateNowPlaying()
    }

    func seek(_ seconds: Double) {
        let s = max(0, min(seconds, duration > 0 ? duration - 0.5 : seconds))
        time = s
        player.seek(to: CMTime(seconds: s, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
    }

    func skip(_ delta: Double) { seek(time + delta) }

    func setSpeed(_ s: Float) {
        speed = s
        AppSettings.shared.set(\.speed, Double(s))
        if isPlaying { player.rate = s }
    }

    func setAudioOnly(_ on: Bool) {
        audioOnly = on
        reload()
    }

    func setSleep(minutes: Int?) {
        sleepAtEnd = false
        sleepAt = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
        showToast(minutes.map { "Sleep timer: \($0) min" } ?? "Sleep timer off")
    }

    func setSleepAtEnd() {
        sleepAt = nil
        sleepAtEnd = true
        showToast("Stops at the end of this video")
    }

    func close() {
        saveProgress()
        loadTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        withAnimation(Motion.spring) {
            current = nil
            expanded = false
        }
        details = nil
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func playNext(_ v: Video) {
        queue.removeAll { $0.id == v.id }
        queue.insert(v, at: 0)
        showToast("Playing next")
    }

    func addToQueue(_ v: Video) {
        guard !queue.contains(where: { $0.id == v.id }) else { return }
        queue.append(v)
        showToast("Added to queue")
    }

    func next() {
        if !queue.isEmpty {
            play(queue.removeFirst(), expand: expanded)
        } else if let n = details?.related.first {
            play(n, expand: expanded)
        }
    }

    func showToast(_ text: String) {
        withAnimation(Motion.spring) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toast == text { withAnimation(Motion.spring) { self?.toast = nil } }
        }
    }

    // MARK: Ticking

    private func tick(_ t: CMTime) {
        guard current != nil else { return }
        let s = t.seconds
        if s.isFinite { time = s }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        isPlaying = player.rate > 0
        tickCount += 1
        if isPlaying {
            pendingWatch += 0.25
            if tickCount % 40 == 0 {
                Library.shared.addWatch(pendingWatch, channel: current?.channel)
                pendingWatch = 0
                saveProgress()
            }
        }
        for seg in segments where time >= seg.start && time < seg.end - 0.5 && abs(time - lastSkip) > 2 {
            lastSkip = seg.end
            seek(seg.end)
            showToast("Skipped \(seg.label)")
            break
        }
        if let at = sleepAt, Date() >= at {
            sleepAt = nil
            pause()
        }
    }

    private func saveProgress() {
        guard let v = current, time > 5 else { return }
        if duration > 0 && time > duration - 20 {
            Library.shared.setProgress(v.id, nil)
        } else {
            Library.shared.setProgress(v.id, time)
        }
    }

    @objc private func itemEnded(_ note: Notification) {
        guard (note.object as? AVPlayerItem) === player.currentItem else { return }
        if let v = current { Library.shared.setProgress(v.id, nil) }
        if sleepAtEnd {
            sleepAtEnd = false
            pause()
            return
        }
        if !queue.isEmpty || AppSettings.shared.d.autoplay { next() } else { isPlaying = false }
    }

    // MARK: Layers, PiP and background audio

    func attachMain(_ layer: AVPlayerLayer) {
        layer.player = player
        guard mainLayer !== layer else { return }
        mainLayer = layer
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let c = AVPictureInPictureController(playerLayer: layer)
            c?.canStartPictureInPictureAutomaticallyFromInline = true
            c?.delegate = self
            pip = c
        }
    }

    func startPiP() { pip?.startPictureInPicture() }
    var pipPossible: Bool { pip?.isPictureInPicturePossible ?? false }

    @objc private func didEnterBackground() {
        guard current != nil, !pipActive else { return }
        let wasPlaying = isPlaying
        detachedLayers = allLayers()
        detachedLayers.forEach { $0.player = nil }
        if wasPlaying { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.player.playImmediately(atRate: self.speed) } }
    }

    @objc private func willEnterForeground() {
        detachedLayers.forEach { $0.player = player }
        detachedLayers = []
    }

    @ObservationIgnored private var layers = NSHashTable<AVPlayerLayer>.weakObjects()
    func register(_ layer: AVPlayerLayer) { layers.add(layer); layer.player = player }
    private func allLayers() -> [AVPlayerLayer] { layers.allObjects + (mainLayer.map { [$0] } ?? []) }

    // MARK: Lock screen

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        c.skipForwardCommand.preferredIntervals = [10]
        c.skipForwardCommand.addTarget { [weak self] _ in self?.skip(10); return .success }
        c.skipBackwardCommand.preferredIntervals = [10]
        c.skipBackwardCommand.addTarget { [weak self] _ in self?.skip(-10); return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            if let e = e as? MPChangePlaybackPositionCommandEvent { self?.seek(e.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let v = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: v.title,
            MPMediaItemPropertyArtist: v.channel,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: time,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(speed) : 0
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        if let url = v.thumbURL {
            Task {
                guard let result = try? await URLSession.shared.data(from: url), let image = UIImage(data: result.0) else { return }
                let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                await MainActor.run {
                    guard self.current?.id == v.id else { return }
                    MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = art
                }
            }
        }
    }
}

extension PlayerModel: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ c: AVPictureInPictureController) { pipActive = true }
    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) { pipActive = false }
}

/// A UIView whose layer is an AVPlayerLayer.
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct VideoSurface: UIViewRepresentable {
    var main: Bool = true
    var gravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        v.backgroundColor = .black
        v.playerLayer.videoGravity = gravity
        if main { PlayerModel.shared.attachMain(v.playerLayer) } else { PlayerModel.shared.register(v.playerLayer) }
        return v
    }

    func updateUIView(_ v: PlayerLayerView, context: Context) {
        v.playerLayer.videoGravity = gravity
        if v.playerLayer.player == nil && UIApplication.shared.applicationState == .active {
            v.playerLayer.player = PlayerModel.shared.player
        }
    }
}
