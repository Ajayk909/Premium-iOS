import Foundation
import AVFoundation
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

/// Turns a video ID into something AVPlayer can play, using YouTubeKit.
enum Streams {
    static func item(for id: String, audioOnly: Bool, maxHeight: Int) async throws -> AVPlayerItem {
        let yt = YouTube(videoID: id, methods: [.local, .remote])

        // 1. HLS: adaptive quality with sound, best for AVPlayer.
        if !audioOnly, let hls = try? await yt.livestreams.first {
            let item = AVPlayerItem(url: hls.url)
            item.preferredMaximumResolution = CGSize(width: maxHeight * 16 / 9, height: maxHeight)
            return item
        }

        let streams = try await yt.streams

        if audioOnly, let a = streams.filterAudioOnly().filter({ $0.isNativelyPlayable }).highestAudioBitrateStream() {
            try? await a.waitUntilAvailable()
            return AVPlayerItem(url: a.url)
        }

        // 2. Separate HD video + audio, joined into one item.
        let video = streams.filterVideoOnly()
            .filter { $0.isNativelyPlayable && $0.fileExtension == .mp4 && ($0.videoResolution ?? 0) <= maxHeight }
            .highestResolutionStream()
        let audio = streams.filterAudioOnly().filter { $0.isNativelyPlayable }.highestAudioBitrateStream()
        if let video, let audio {
            try? await video.waitUntilAvailable()
            if let item = try? await compose(video: video.url, audio: audio.url) { return item }
        }

        // 3. Single file with video and sound (usually 360p).
        if let p = streams.filterVideoAndAudio().filter({ $0.isNativelyPlayable }).highestResolutionStream() {
            try? await p.waitUntilAvailable()
            return AVPlayerItem(url: p.url)
        }
        throw YTError.noStream
    }

    private static func compose(video: URL, audio: URL) async throws -> AVPlayerItem {
        let va = AVURLAsset(url: video)
        let aa = AVURLAsset(url: audio)
        guard let vt = try await va.loadTracks(withMediaType: .video).first,
              let at = try await aa.loadTracks(withMediaType: .audio).first else { throw YTError.noStream }
        let vDur = try await va.load(.duration)
        let aDur = try await aa.load(.duration)
        let comp = AVMutableComposition()
        let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        try cv?.insertTimeRange(CMTimeRange(start: .zero, duration: vDur), of: vt, at: .zero)
        try ca?.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(vDur, aDur)), of: at, at: .zero)
        cv?.preferredTransform = try await vt.load(.preferredTransform)
        return AVPlayerItem(asset: comp)
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

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private let recognizer = SFSpeechRecognizer()
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
