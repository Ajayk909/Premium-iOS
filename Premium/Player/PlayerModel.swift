import SwiftUI
import AVKit
import CoreImage
import MediaPlayer
import Observation
import YouTubeKit

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
    /// -1 off, 0 end of video, otherwise minutes.
    var sleepChoice = -1
    var segments: [SkipSegment] = []
    var toast: String?
    var pipActive = false
    /// Four colours sampled from the video (top-left, top-right, bottom-left, bottom-right) for ambient mode.
    var ambient: [Color] = []
    /// nil = Auto. Otherwise the highest picture height allowed (1080, 720, …).
    var qualityCap: Int?
    var isHLS = false
    /// Every quality this iPhone can play for the current video, best first.
    var qualities: [VideoChoice] = []
    var playingQuality: VideoChoice?
    var captionTracks: [CaptionTrack] = []
    var captionTrack: CaptionTrack?
    var captionText: String?
    var locked = false

    let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var pip: AVPictureInPictureController?
    @ObservationIgnored private weak var mainLayer: AVPlayerLayer?
    @ObservationIgnored private var detachedLayers: [AVPlayerLayer] = []
    @ObservationIgnored private var lastSkip: Double = -10
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private var pendingWatch: Double = 0
    @ObservationIgnored private var videoOutput: AVPlayerItemVideoOutput?
    @ObservationIgnored private let ambientQueue = DispatchQueue(label: "premium.ambient", qos: .utility)
    @ObservationIgnored private let ciContext = CIContext(options: [.workingColorSpace: NSNull()])
    @ObservationIgnored private var sampling = false
    @ObservationIgnored private var cues: [Cue] = []
    @ObservationIgnored private var streamSet: StreamSet?

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
        captionTracks = []
        qualities = []
        playingQuality = nil
        streamSet = nil
        hlsURL = nil
        captionTrack = nil
        captionText = nil
        cues = []
        locked = false
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
        let autoCap = AppSettings.shared.d.dataSaver ? 480 : 1080
        let cap = qualityCap
        let cats = AppSettings.shared.d.sponsorCategories
        loadTask = Task { @MainActor in
            // Details, SponsorBlock and captions load on their own so the page fills in right away.
            Task { @MainActor in await self.loadExtras(v, cats: cats) }
            do {
                var item: AVPlayerItem?
                let yt = YouTube(videoID: v.id, methods: [.local, .remote])
                // 1. Start with HLS as soon as it's ready (fast). 2. Look up the HD streams in the background.
                if !audioOnly, let h = await Streams.quickHLS(yt) {
                    guard !Task.isCancelled, self.current?.id == v.id else { return }
                    let it = AVPlayerItem(url: h)
                    let limit = cap ?? (autoCap < 1080 ? autoCap : nil)
                    if let limit { it.preferredMaximumResolution = CGSize(width: limit * 16 / 9 + 2, height: limit + 2) }
                    item = it
                    self.isHLS = true
                    self.hlsURL = h
                    self.playingQuality = nil
                    Task { @MainActor in await self.loadQualities(yt, hls: h, for: v.id) }
                } else {
                    let set = try await Streams.load(yt, hls: nil)
                    guard !Task.isCancelled, self.current?.id == v.id else { return }
                    self.streamSet = set
                    self.hlsURL = set.hls
                    let choice = Streams.choose(set, height: cap, autoCap: autoCap)
                    if let it = try? await Streams.item(set, choice: choice, audioOnly: audioOnly) {
                        item = it
                        self.isHLS = false
                        self.qualities = set.videos
                        self.playingQuality = audioOnly ? nil : choice
                    }
                }
                guard let item else { throw YTError.noStream }
                guard !Task.isCancelled, self.current?.id == v.id else { return }
                self.attach(item)
                self.ambient = []
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
                if !Task.isCancelled { self.error = "Couldn't play this video.\n" + ((error as? LocalizedError)?.errorDescription ?? String(describing: error)).prefix(160) }
            }
            if self.current?.id == v.id { self.loading = false }
            self.updateNowPlaying()
        }
    }

    @MainActor
    private func loadExtras(_ v: Video, cats: [String]) async {
        if let d = try? await InnerTube.shared.details(v.id), self.current?.id == v.id {
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
        let s = await SponsorBlock.segments(v.id, categories: cats)
            if self.current?.id == v.id { self.segments = s }
        // Captions are only looked up if you use them (fewer requests = less chance of YouTube's bot check).
        guard AppSettings.shared.d.captionLanguage != nil else { updateNowPlaying(); return }
        let t = await InnerTube.shared.captionTracks(v.id)
            if self.current?.id == v.id {
                self.captionTracks = t
                if let lang = AppSettings.shared.d.captionLanguage,
                   let match = t.first(where: { $0.lang == lang && !$0.auto }) ?? t.first(where: { $0.lang == lang }) {
                    self.selectCaption(match, remember: false)
                }
            }
        updateNowPlaying()
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

    // MARK: Quality & captions

    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    private func attach(_ item: AVPlayerItem) {
        // If a stream fails after it starts, switch to YouTube's HLS feed automatically.
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            guard it.status == .failed else { return }
            DispatchQueue.main.async { self?.fallBackToHLS() }
        }
        let out = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        item.add(out)
        videoOutput = out
        player.replaceCurrentItem(with: item)
    }

    @ObservationIgnored private var hlsURL: URL?

    /// Builds the quality list: everything in the HLS feed (with real frame rates) plus any
    /// higher HD streams (4K/8K AV1) this iPhone can decode.
    @MainActor
    private func loadQualities(_ yt: YouTube, hls: URL, for id: String) async {
        let fromHLS = await Streams.hlsVariants(hls)
        if current?.id == id { qualities = merge(fromHLS, []) }
        if let set = try? await Streams.load(yt, hls: hls), current?.id == id {
            streamSet = set
            qualities = merge(fromHLS, set.videos)
        }
    }

    private func merge(_ hls: [VideoChoice], _ adaptive: [VideoChoice]) -> [VideoChoice] {
        var byHeight: [Int: VideoChoice] = [:]
        for c in adaptive { byHeight[c.height] = c }
        for c in hls {
            if let a = byHeight[c.height], a.hfr && !c.hfr { continue }
            byHeight[c.height] = c
        }
        return byHeight.values.sorted { $0.height > $1.height }
    }

    /// Switch quality (or audio-only), keeping your place.
    private func switchStreams(to choice: VideoChoice? = nil) {
        guard let v = current else { return }
        let at = time
        let wasPlaying = isPlaying || loading
        loading = true
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            do {
                let item: AVPlayerItem
                var playing: VideoChoice? = nil
                if !self.audioOnly, let h = self.hlsURL, choice == nil || choice?.fromHLS == true {
                    item = AVPlayerItem(url: h)
                    if let c = choice { item.preferredMaximumResolution = CGSize(width: c.height * 16 / 9 + 2, height: c.height + 2) }
                    self.isHLS = true
                    playing = choice
                } else {
                    guard let set = self.streamSet else { self.showToast("Still loading HD streams — try again in a moment"); self.loading = false; return }
                    let pick = choice ?? Streams.choose(set, height: self.qualityCap, autoCap: AppSettings.shared.d.dataSaver ? 480 : 1080)
                    item = try await Streams.item(set, choice: pick, audioOnly: self.audioOnly)
                    self.isHLS = false
                    playing = self.audioOnly ? nil : pick
                }
                guard !Task.isCancelled, self.current?.id == v.id else { return }
                self.attach(item)
                self.playingQuality = playing
                await self.player.seek(to: CMTime(seconds: at, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                if wasPlaying { self.player.playImmediately(atRate: self.speed) }
            } catch {
                self.showToast("That quality couldn't be played")
            }
            self.loading = false
        }
    }

    private func fallBackToHLS() {
        guard !isHLS, hlsURL != nil else { return }
        showToast("Switched to Auto quality")
        qualityCap = nil
        switchStreams(to: nil)
    }

    func setQuality(_ height: Int?) {
        qualityCap = height
        let target = height.flatMap { h in qualities.first { $0.height == h } }
        if isHLS, target == nil || target?.fromHLS == true, let item = player.currentItem {
            // Same HLS stream: just change the limit, no reload.
            item.preferredMaximumResolution = target.map { CGSize(width: $0.height * 16 / 9 + 2, height: $0.height + 2) } ?? .zero
            playingQuality = target
        } else {
            switchStreams(to: target)
        }
        showToast(target.map { "Quality: \($0.label)" } ?? "Quality: Auto")
    }

    func selectCaption(_ track: CaptionTrack?, remember: Bool = true) {
        captionTrack = track
        captionText = nil
        cues = []
        if remember { AppSettings.shared.set(\.captionLanguage, track?.lang) }
        guard let track else { return }
        Task { @MainActor in
            let c = await InnerTube.shared.cues(track)
            guard self.captionTrack == track else { return }
            self.cues = c
            if c.isEmpty { self.showToast("Couldn't load captions for this video") }
        }
    }

    func loadCaptionTracks() async {
        guard captionTracks.isEmpty, let v = current else { return }
        let t = await InnerTube.shared.captionTracks(v.id)
        if current?.id == v.id { captionTracks = t }
    }

    func toggleCaptions() {
        if captionTrack == nil && captionTracks.isEmpty {
            Task { @MainActor in
                await self.loadCaptionTracks()
                if self.captionTracks.isEmpty { self.showToast("This video has no captions") } else { self.toggleCaptions() }
            }
            return
        }
        if captionTrack != nil {
            selectCaption(nil)
        } else if let t = captionTracks.first(where: { $0.lang == (AppSettings.shared.d.captionLanguage ?? "en") }) ?? captionTracks.first(where: { !$0.auto }) ?? captionTracks.first {
            selectCaption(t)
        } else {
            showToast("This video has no captions")
        }
    }

    private func updateCaption() {
        guard !cues.isEmpty else { if captionText != nil { captionText = nil }; return }
        var lo = 0, hi = cues.count - 1, found: Cue?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if cues[mid].start <= time { found = cues[mid]; lo = mid + 1 } else { hi = mid - 1 }
        }
        let text = (found.map { time < $0.end ? $0.text : nil }) ?? nil
        if text != captionText { captionText = text }
    }

    // MARK: Ambient mode

    private func sampleAmbient() {
        guard AppSettings.shared.d.ambient, expanded, !audioOnly, !sampling, let out = videoOutput else { return }
        let t = player.currentTime()
        sampling = true
        ambientQueue.async { [weak self] in
            guard let self else { return }
            defer { DispatchQueue.main.async { self.sampling = false } }
            guard let pb = out.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) else { return }
            let img = CIImage(cvPixelBuffer: pb)
            let e = img.extent
            let w = e.width / 2, h = e.height / 2
            // Core Image's origin is bottom-left.
            let rects = [CGRect(x: e.minX, y: e.minY + h, width: w, height: h),
                         CGRect(x: e.minX + w, y: e.minY + h, width: w, height: h),
                         CGRect(x: e.minX, y: e.minY, width: w, height: h),
                         CGRect(x: e.minX + w, y: e.minY, width: w, height: h)]
            let colors = rects.compactMap { self.average(img, $0) }
            guard colors.count == 4 else { return }
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 1.1)) { self.ambient = colors }
            }
        }
    }

    private func average(_ img: CIImage, _ r: CGRect) -> Color? {
        guard let f = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: img, kCIInputExtentKey: CIVector(cgRect: r)]),
              let o = f.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        ciContext.render(o, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
        UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
            .getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
        return Color(hue: Double(hue), saturation: Double(min(1, sat * 1.4)), brightness: Double(max(0.35, min(1, bri * 1.2))))
    }

    func setSpeed(_ s: Float) {
        speed = s
        AppSettings.shared.set(\.speed, Double(s))
        if isPlaying { player.rate = s }
    }

    func setAudioOnly(_ on: Bool) {
        audioOnly = on
        switchStreams()
    }

    func setSleep(minutes: Int?) {
        sleepAtEnd = false
        sleepChoice = minutes ?? -1
        sleepAt = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
        showToast(minutes.map { "Sleep timer: \($0) min" } ?? "Sleep timer off")
    }

    func setSleepAtEnd() {
        sleepAt = nil
        sleepAtEnd = true
        sleepChoice = 0
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
        } else if let n = details?.related.first(where: { $0.id != current?.id && !$0.isShort }) {
            play(n, expand: expanded)
        } else {
            showToast("Up next is still loading")
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
        if s.isFinite, s != time { time = s }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0, d != duration { duration = d }
        let playing = player.rate > 0
        if playing != isPlaying { isPlaying = playing }
        tickCount += 1
        updateCaption()
        if tickCount % 2 == 0 { sampleAmbient() }
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
