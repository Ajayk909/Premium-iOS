import Foundation

struct Video: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var channel: String = ""
    var channelId: String? = nil
    var channelAvatar: String? = nil
    var thumbnail: String? = nil
    var duration: String? = nil
    var views: String? = nil
    var published: String? = nil
    var isLive: Bool = false
    var isShort: Bool = false

    var thumbURL: URL? {
        URL(string: thumbnail ?? "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
    }

    /// Big, sharp thumbnail for the watch page and widgets.
    var largeThumbURL: URL? {
        URL(string: "https://i.ytimg.com/vi/\(id)/hq720.jpg") ?? thumbURL
    }

    var meta: String {
        [channel, views, published].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var shareURL: URL { URL(string: isShort ? "https://youtube.com/shorts/\(id)" : "https://youtu.be/\(id)")! }

    var durationSeconds: Int? {
        guard let duration, !duration.isEmpty else { return nil }
        let parts = duration.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}

struct Channel: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var avatar: String? = nil
    var subscribers: String? = nil
}

struct Chapter: Identifiable, Hashable {
    var title: String
    var start: Double
    var thumbnail: String?
    var id: Double { start }
}

struct Comment: Identifiable, Hashable {
    var id: String
    var author: String
    var avatar: String?
    var text: String
    var likes: String
    var published: String
    var replies: String
}

struct VideoDetails {
    var video: Video
    var description: String
    var views: String
    var date: String
    var likes: String?
    var channel: Channel?
    var chapters: [Chapter]
    var related: [Video]
    var commentsToken: String?
    var commentCount: String?
}

struct CaptionTrack: Identifiable, Hashable {
    var name: String
    var lang: String
    var url: String
    var auto: Bool
    var id: String { url }
}

struct Cue {
    var start: Double
    var end: Double
    var text: String
}

struct Page {
    var items: [Video]
    var continuation: String?
}

struct ChannelPage {
    var channel: Channel
    var banner: String?
    var handle: String?
    var description: String?
    var videos: Page
}

struct Playlist: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var name: String
    var videos: [Video] = []
    /// Set when the playlist was imported from your YouTube account.
    var sourceID: String? = nil
}

func formatTime(_ s: Double) -> String {
    guard s.isFinite, s >= 0 else { return "0:00" }
    let t = Int(s)
    let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

func formatDuration(_ seconds: Double) -> String {
    let m = Int(seconds / 60)
    return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
}
