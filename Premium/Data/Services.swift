import Foundation
import AVFoundation
import VideoToolbox
import Speech
import Observation
import YouTubeKit

// MARK: - SponsorBlock

struct SkipSegment: Hashable {
    var start: Double
    var end: Double
    var category: String

    var label: String {
        switch category {
        case "sponsor": return "sponsor"
        case "selfpromo": return "self-promo"
        case "interaction": return "subscribe reminder"
        case "intro": return "intro"
        case "outro": return "outro"
        case "music_offtopic": return "non-music part"
        default: return "segment"
        }
    }
}

enum SponsorBlock {
    static let allCategories: [(String, String)] = [
        ("sponsor", "Sponsors"), ("selfpromo", "Self-promotion"), ("interaction", "Like & subscribe reminders"),
        ("intro", "Intros"), ("outro", "Outros / end cards"), ("music_offtopic", "Non-music parts in music videos")
    ]

    static func segments(_ id: String, categories: [String]) async -> [SkipSegment] {
        guard !categories.isEmpty,
              let cats = try? JSONSerialization.data(withJSONObject: categories),
              let catString = String(data: cats, encoding: .utf8)?.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: "https://sponsor.ajay.app/api/skipSegments?videoID=\(id)&categories=\(catString)"),
              let result = try? await URLSession.shared.data(from: url),
              let list = try? JSONSerialization.jsonObject(with: result.0) as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let seg = item["segment"] as? [Double], seg.count == 2 else { return nil }
            return SkipSegment(start: seg[0], end: seg[1], category: item["category"] as? String ?? "sponsor")
        }
    }
}

// MARK: - Streams

/// One picture quality the iPhone can play natively.
struct VideoChoice: Identifiable, Hashable {
    var height: Int
    var hfr: Bool
    var av1: Bool
    var url: URL
    /// From YouTube's HLS feed (switches instantly) rather than the separate HD streams.
    var fromHLS = false
    var id: Int { height }

    var label: String {
        let base: String
        switch height {
        case 4320...: base = "8K"
        case 2160...: base = "4K"
        case 1440...: base = "1440p"
        default: base = "\(height)p"
        }
        return base + (hfr ? "60" : "")
    }
}

/// Everything we found for a video, kept so quality changes are instant (no new lookup).
struct StreamSet {
    var videos: [VideoChoice]
    var audio: URL?
    var progressive: URL?
    var hls: URL?
    var availableAt: Date
}

/// Turns a video ID into something AVPlayer can play, using YouTubeKit.
/// We use the separate video + audio streams (same as YouTube's own app), never the HLS feed,
/// which can carry stitched-in ads.
enum Streams {
    /// YouTube format codes that are 50/60 fps.
    private static let hfrTags: Set<Int> = [298, 299, 302, 303, 308, 315, 334, 335, 336, 337, 694, 695, 696, 697, 698, 699, 700, 701, 702]

    /// Reads the HLS master playlist to list real qualities with their frame rates.
    static func hlsVariants(_ url: URL) async -> [VideoChoice] {
        guard let r = try? await URLSession.shared.data(from: url), let text = String(data: r.0, encoding: .utf8) else { return [] }
        var best: [Int: VideoChoice] = [:]
        for line in text.split(separator: "\n") where line.hasPrefix("#EXT-X-STREAM-INF:") {
            let l = String(line)
            guard let res = l.range(of: #"RESOLUTION=(\d+)x(\d+)"#, options: .regularExpression) else { continue }
            let dims = l[res].replacingOccurrences(of: "RESOLUTION=", with: "").split(separator: "x").compactMap { Int($0) }
            guard dims.count == 2 else { continue }
            let h = min(dims[0], dims[1])
            var fps = 30.0
            if let fr = l.range(of: #"FRAME-RATE=[\d.]+"#, options: .regularExpression) {
                fps = Double(l[fr].replacingOccurrences(of: "FRAME-RATE=", with: "")) ?? 30
            }
            let codecs = l.range(of: #"CODECS="[^"]*""#, options: .regularExpression).map { String(l[$0]) } ?? ""
            if codecs.contains("vp09") && !VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9) { continue }
            if codecs.contains("av01") && !VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1) { continue }
            let choice = VideoChoice(height: h, hfr: fps > 31, av1: codecs.contains("av01"), url: url, fromHLS: true)
            if let cur = best[h], cur.hfr && !choice.hfr { continue }
            best[h] = choice
        }
        return best.values.sorted { $0.height > $1.height }
    }

    static func load(_ id: String) async throws -> StreamSet {
        try await load(YouTube(videoID: id, methods: [.local, .remote]), hls: nil)
    }

    /// Fast path: YouTube's HLS feed is usually ready first, so playback can start right away.
    static func quickHLS(_ yt: YouTube) async -> URL? {
        try? await yt.livestreams.first?.url
    }

    /// The separate HD streams (for 4K/8K and exact quality picks). Slower, so it runs in the background.
    static func load(_ yt: YouTube, hls known: URL?) async throws -> StreamSet {
        let streams = try await yt.streams
        let hls = known ?? (try? await yt.livestreams.first?.url)
        var best: [Int: (choice: VideoChoice, score: Int)] = [:]
        for s in streams.filterVideoOnly() where s.isNativelyPlayable && s.fileExtension == .mp4 {
            guard let h = s.videoResolution else { continue }
            let tag = URLComponents(url: s.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "itag" }?.value.flatMap(Int.init) ?? 0
            let av1: Bool
            if case .some(.av1) = s.videoCodec { av1 = true } else { av1 = false }
            let hfr = hfrTags.contains(tag)
            let score = (hfr ? 1_000_000_000 : 0) + (av1 ? 100_000_000 : 0) + (s.bitrate ?? s.averageBitrate ?? 0)
            if best[h] == nil || score > best[h]!.score {
                best[h] = (VideoChoice(height: h, hfr: hfr, av1: av1, url: s.url), score)
            }
        }
        let audio = streams.filterAudioOnly().filter { $0.isNativelyPlayable }.highestAudioBitrateStream()?.url
        let progressive = streams.filterVideoAndAudio().filter { $0.isNativelyPlayable }.highestResolutionStream()?.url
        let available = streams.map(\.availableAt).max() ?? Date()
        return StreamSet(videos: best.values.map { $0.choice }.sorted { $0.height > $1.height },
                         audio: audio, progressive: progressive, hls: hls, availableAt: available)
    }

    /// Picks the quality: the one asked for, or Auto (best up to 1080p, or 480p with data saver).
    static func choose(_ set: StreamSet, height: Int?, autoCap: Int) -> VideoChoice? {
        if let height, let exact = set.videos.first(where: { $0.height == height }) { return exact }
        let cap = height ?? autoCap
        return set.videos.first { $0.height <= cap } ?? set.videos.last
    }

    /// YouTube's stream servers expect the same browser ID as the client that asked for the stream.
    static func asset(_ url: URL) -> AVURLAsset {
        let client = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "c" }?.value ?? ""
        let ua: String
        switch client {
        case "TVHTML5": ua = "Mozilla/5.0 (SMART-TV; Linux; Tizen 2.4.0) AppleWebKit/538.1 (KHTML, like Gecko) Version/2.4.0 TV Safari/538.1"
        case "VISIONOS": ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        case "IOS": ua = "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)"
        case "ANDROID", "ANDROID_VR": ua = "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip"
        default: ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        }
        return AVURLAsset(url: url, options: [AVURLAssetHTTPUserAgentKey: ua, AVURLAssetPreferPreciseDurationAndTimingKey: false])
    }

    static func item(_ set: StreamSet, choice: VideoChoice?, audioOnly: Bool) async throws -> AVPlayerItem {
        let wait = set.availableAt.timeIntervalSinceNow
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(min(wait, 15) * 1_000_000_000)) }
        if audioOnly, let a = set.audio { return AVPlayerItem(asset: asset(a)) }
        if let choice, let a = set.audio, let item = try? await compose(video: choice.url, audio: a) { return item }
        if let h = set.hls { return AVPlayerItem(url: h) }
        if let p = set.progressive { return AVPlayerItem(asset: asset(p)) }
        throw YTError.noStream
    }

    /// Last resort: YouTube's HLS feed.
    static func hlsFallback(_ id: String) async throws -> AVPlayerItem {
        let yt = YouTube(videoID: id, methods: [.local, .remote])
        guard let hls = try await yt.livestreams.first else { throw YTError.noStream }
        return AVPlayerItem(url: hls.url)
    }

    /// Simple single-item helper used by Shorts.
    static func item(for id: String, audioOnly: Bool, maxHeight: Int) async throws -> AVPlayerItem {
        let yt = YouTube(videoID: id, methods: [.local, .remote])
        if !audioOnly, let h = await quickHLS(yt) { return AVPlayerItem(url: h) }
        let set = try await load(yt, hls: nil)
        return try await item(set, choice: choose(set, height: nil, autoCap: maxHeight), audioOnly: audioOnly)
    }

    private static func compose(video: URL, audio: URL) async throws -> AVPlayerItem {
        let va = asset(video)
        let aa = asset(audio)
        async let vTracks = va.loadTracks(withMediaType: .video)
        async let aTracks = aa.loadTracks(withMediaType: .audio)
        async let vDurLoad = va.load(.duration)
        async let aDurLoad = aa.load(.duration)
        guard let vt = try await vTracks.first, let at = try await aTracks.first else { throw YTError.noStream }
        let vDur = try await vDurLoad
        let aDur = try await aDurLoad
        let comp = AVMutableComposition()
        let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        try cv?.insertTimeRange(CMTimeRange(start: .zero, duration: vDur), of: vt, at: .zero)
        try ca?.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(vDur, aDur)), of: at, at: .zero)
        cv?.preferredTransform = try await vt.load(.preferredTransform)
        let item = AVPlayerItem(asset: comp)
        item.preferredForwardBufferDuration = 8
        return item
    }
}

// MARK: - Roku

struct RokuDevice: Identifiable, Codable, Hashable {
    var ip: String
    var name: String
    var id: String { ip }
}

/// Finds Roku TVs on the Wi-Fi and controls them with Roku's External Control API (port 8060).
/// Casting opens the video in the TV's own YouTube app, so it plays at full quality.
@Observable
final class Roku {
    static let shared = Roku()

    var devices: [RokuDevice] = []
    var current: RokuDevice?
    var scanning = false
    var lastError: String?

    init() {
        if let ip = AppSettings.shared.d.rokuIP {
            let d = RokuDevice(ip: ip, name: AppSettings.shared.d.rokuName ?? "Roku TV")
            current = d
            devices = [d]
        }
    }

    func select(_ d: RokuDevice) {
        current = d
        AppSettings.shared.set(\.rokuIP, d.ip)
        AppSettings.shared.set(\.rokuName, d.name)
    }

    func forget() {
        current = nil
        AppSettings.shared.set(\.rokuIP, nil)
    }

    func scan() {
        guard !scanning else { return }
        guard let ip = Roku.localIP() else { lastError = "Connect to Wi-Fi to find your TV."; return }
        let base = ip.split(separator: ".").prefix(3).joined(separator: ".")
        scanning = true
        lastError = nil
        Task { @MainActor in
            let found = await withTaskGroup(of: RokuDevice?.self) { group -> [RokuDevice] in
                for i in 1...254 {
                    group.addTask { await Roku.probe("\(base).\(i)") }
                }
                var list: [RokuDevice] = []
                for await d in group { if let d { list.append(d) } }
                return list
            }
            self.devices = found.sorted { $0.name < $1.name }
            if self.current == nil, let only = found.first, found.count == 1 { self.select(only) }
            if found.isEmpty { self.lastError = "No Roku found. Make sure the TV is on and on the same Wi-Fi." }
            self.scanning = false
        }
    }

    func addManual(_ ip: String) {
        Task { @MainActor in
            if let d = await Roku.probe(ip.trimmingCharacters(in: .whitespaces)) {
                if !self.devices.contains(d) { self.devices.append(d) }
                self.select(d)
            } else {
                self.lastError = "Couldn't reach a Roku at \(ip)."
            }
        }
    }

    static func probe(_ ip: String) async -> RokuDevice? {
        guard let url = URL(string: "http://\(ip):8060/query/device-info") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 1.5)
        req.httpMethod = "GET"
        guard let result = try? await URLSession.shared.data(for: req),
              let xml = String(data: result.0, encoding: .utf8), xml.contains("<device-info") else { return nil }
        func tag(_ name: String) -> String? {
            guard let a = xml.range(of: "<\(name)>"), let b = xml.range(of: "</\(name)>", range: a.upperBound..<xml.endIndex) else { return nil }
            let v = String(xml[a.upperBound..<b.lowerBound])
            return v.isEmpty ? nil : v
        }
        let name = tag("user-device-name") ?? tag("friendly-device-name") ?? tag("model-name") ?? "Roku TV"
        return RokuDevice(ip: ip, name: name)
    }

    private func send(_ path: String) {
        guard let d = current, let url = URL(string: "http://\(d.ip):8060/\(path)") else { return }
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.httpMethod = "POST"
        URLSession.shared.dataTask(with: req).resume()
    }

    func key(_ k: String) { send("keypress/\(k)") }

    /// 837 is the YouTube channel on Roku.
    func cast(_ videoID: String, at seconds: Double = 0) {
        var path = "launch/837?contentId=\(videoID)&mediaType=live"
        if seconds > 5 { path += "&t=\(Int(seconds))" }
        send(path)
    }

    static func localIP() -> String? {
        var result: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = ptr.pointee
            guard let addr = i.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: i.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            if ip.hasPrefix("169.254") { continue }
            result = ip
            if name == "en0" { break }
        }
        return result
    }
}

// MARK: - Voice search

@Observable
final class VoiceSearch {
    var transcript = ""
    var listening = false
    var level: CGFloat = 0
    var denied = false

    private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer()
    @ObservationIgnored private var silence: DispatchWorkItem?
    @ObservationIgnored private var onDone: ((String) -> Void)?

    func start(_ done: @escaping (String) -> Void) {
        onDone = done
        transcript = ""
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else { self.denied = true; return }
                self.begin()
            }
        }
    }

    private func begin() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
                guard let data = buffer.floatChannelData?[0] else { return }
                let n = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<n { sum += data[i] * data[i] }
                let rms = sqrt(sum / Float(max(n, 1)))
                DispatchQueue.main.async { self?.level = min(1, CGFloat(rms) * 12) }
            }
            engine.prepare()
            try engine.start()
            listening = true
            task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        self.armSilence()
                        if result.isFinal { self.finish() }
                    }
                    if error != nil, self.listening { self.finish() }
                }
            }
            armSilence(after: 4)
        } catch {
            stop()
        }
    }

    private func armSilence(after seconds: Double = 1.4) {
        silence?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.finish() }
        silence = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    private func finish() {
        guard listening else { return }
        let text = transcript
        stop()
        if !text.isEmpty { onDone?(text) }
    }

    func stop() {
        silence?.cancel()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        listening = false
        level = 0
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }
}
