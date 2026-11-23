import Foundation

enum YTError: LocalizedError {
    case badResponse
    case noStream
    var errorDescription: String? {
        switch self {
        case .badResponse: return "YouTube sent something unexpected."
        case .noStream: return "Couldn't find a playable stream for this video."
        }
    }
}

/// Talks to YouTube's own web API (the same one youtube.com uses) for search, feeds,
/// channels, video pages and comments. Stream URLs come from YouTubeKit (see Streams.swift).
final class InnerTube {
    static let shared = InnerTube()

    private let clientVersion = "2.20251110.01.00"
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    private var region: String { Locale.current.region?.identifier ?? "CA" }

    private struct Client {
        var name: String
        var version: String
        var id: String
        var userAgent: String
        var extra: [String: String] = [:]
    }

    private var web: Client { Client(name: "WEB", version: clientVersion, id: "1", userAgent: userAgent) }
    private let ios = Client(name: "IOS", version: "20.10.4", id: "5",
                             userAgent: "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
                             extra: ["deviceMake": "Apple", "deviceModel": "iPhone16,2", "osName": "iPhone", "osVersion": "18.3.2.22D82"])
    private let tv = Client(name: "TVHTML5", version: "7.20250923.13.00", id: "7",
                            userAgent: "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)")

    private func post(_ endpoint: String, _ body: [String: Any], client: Client? = nil) async throws -> [String: Any] {
        let c = client ?? web
        var req = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false")!)
        req.httpMethod = "POST"
        var payload = body
        var ctx: [String: Any] = ["clientName": c.name, "clientVersion": c.version, "hl": "en", "gl": region]
        for (k, v) in c.extra { ctx[k] = v }
        payload["context"] = ["client": ctx]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(c.id, forHTTPHeaderField: "X-YouTube-Client-Name")
        req.setValue(c.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        req.setValue(c.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")
        let (data, _) = try await session.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw YTError.badResponse }
        return obj
    }

    // MARK: Search

    enum Filter: String, CaseIterable, Identifiable {
        case none, today, week, month, short, long, live, shorts
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: return "All"
            case .today: return "Today"
            case .week: return "This week"
            case .month: return "This month"
            case .short: return "Under 4 min"
            case .long: return "Over 20 min"
            case .live: return "Live"
            case .shorts: return "Shorts"
            }
        }
        var params: String? {
            switch self {
            case .none: return nil
            case .today: return "EgIIAg=="
            case .week: return "EgIIAw=="
            case .month: return "EgIIBA=="
            case .short: return "EgIYAQ=="
            case .long: return "EgIYAg=="
            case .live: return "EgJAAQ=="
            case .shorts: return "EgIQCQ=="
            }
        }
    }

    func search(_ query: String, filter: Filter = .none, continuation: String? = nil) async throws -> Page {
        var body: [String: Any] = [:]
        if let continuation {
            body["continuation"] = continuation
        } else {
            body["query"] = query
            if let p = filter.params { body["params"] = p }
        }
        let json = try await post("search", body)
        var items = YTParse.videos(in: json)
        if filter == .shorts { items = items.map { var v = $0; v.isShort = true; return v } }
        return Page(items: items, continuation: YTParse.lastContinuation(in: json))
    }

    func suggestions(_ query: String) async -> [String] {
        guard !query.isEmpty,
              let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://suggestqueries-clients6.youtube.com/complete/search?client=firefox&ds=yt&hl=en&q=\(q)"),
              let result = try? await session.data(from: url),
              let arr = try? JSONSerialization.jsonObject(with: result.0) as? [Any],
              arr.count > 1, let list = arr[1] as? [String] else { return [] }
        return Array(list.prefix(10))
    }

    // MARK: Captions

    func captionTracks(_ id: String) async -> [CaptionTrack] {
        // Different YouTube clients get captions in different situations, so try a few.
        var list: [[String: Any]] = []
        for c in [ios, tv, web] {
            if let json = try? await post("player", ["videoId": id], client: c),
               let l = YTParse.dig(json, "captions", "playerCaptionsTracklistRenderer", "captionTracks") as? [[String: Any]], !l.isEmpty {
                list = l
                break
            }
        }
        return list.compactMap { t in
            guard let url = t["baseUrl"] as? String else { return nil }
            let lang = t["languageCode"] as? String ?? ""
            let auto = (t["kind"] as? String) == "asr"
            let name = YTParse.text(t["name"]) ?? lang
            return CaptionTrack(name: auto ? "\(name)" : name, lang: lang, url: url, auto: auto)
        }
    }

    func cues(_ track: CaptionTrack) async -> [Cue] {
        guard let url = URL(string: track.url.replacingOccurrences(of: "&fmt=srv3", with: "") + "&fmt=json3"),
              let result = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else { return [] }
        var out: [Cue] = []
        for e in events {
            guard let segs = e["segs"] as? [[String: Any]] else { continue }
            let text = segs.compactMap { $0["utf8"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.range(of: #"^\d{2}:\d{2}:\d{2}"#, options: .regularExpression) == nil else { continue }
            let start = Double(e["tStartMs"] as? Int ?? 0) / 1000
            let dur = Double(e["dDurationMs"] as? Int ?? 2000) / 1000
            out.append(Cue(start: start, end: start + dur, text: text))
        }
        return out.sorted { $0.start < $1.start }
    }

    // MARK: Video page

    func details(_ id: String) async throws -> VideoDetails {
        let json = try await post("next", ["videoId": id])
        let primary = YTParse.first("videoPrimaryInfoRenderer", in: json) as? [String: Any]
        let secondary = YTParse.first("videoSecondaryInfoRenderer", in: json) as? [String: Any]
        let owner = YTParse.dig(secondary, "owner", "videoOwnerRenderer") as? [String: Any]

        let title = YTParse.text(primary?["title"]) ?? ""
        let views = YTParse.text(YTParse.dig(primary, "viewCount", "videoViewCountRenderer", "shortViewCount"))
            ?? YTParse.text(YTParse.dig(primary, "viewCount", "videoViewCountRenderer", "viewCount")) ?? ""
        let date = YTParse.text(primary?["relativeDateText"]) ?? YTParse.text(primary?["dateText"]) ?? ""
        var likes: String?
        if let like = YTParse.first("likeButtonViewModel", in: primary ?? [String: Any]()) {
            likes = YTParse.firstString("title", in: like)
        }

        var channel: Channel?
        if let owner, let cid = YTParse.dig(owner, "navigationEndpoint", "browseEndpoint", "browseId") as? String {
            channel = Channel(id: cid,
                              name: YTParse.text(owner["title"]) ?? "",
                              avatar: YTParse.fix((YTParse.dig(owner, "thumbnail", "thumbnails") as? [[String: Any]])?.last?["url"] as? String),
                              subscribers: YTParse.text(owner["subscriberCountText"]))
        }
        let description = YTParse.text(secondary?["attributedDescription"]) ?? YTParse.text(secondary?["description"]) ?? ""

        var chapters: [Chapter] = []
        for c in YTParse.all("chapterRenderer", in: json) {
            let start = (c["timeRangeStartMillis"] as? Double) ?? Double(c["timeRangeStartMillis"] as? Int ?? 0)
            let thumb = (YTParse.dig(c, "thumbnail", "thumbnails") as? [[String: Any]])?.last?["url"] as? String
            let chapter = Chapter(title: YTParse.text(c["title"]) ?? "", start: start / 1000, thumbnail: YTParse.fix(thumb))
            if !chapters.contains(where: { $0.start == chapter.start }) { chapters.append(chapter) }
        }
        chapters.sort { $0.start < $1.start }

        var related = YTParse.videos(in: YTParse.first("secondaryResults", in: json) ?? [String: Any]()).filter { $0.id != id }
        if related.isEmpty { related = YTParse.videos(in: json).filter { $0.id != id } }

        var token: String?
        if let section = YTParse.all("itemSectionRenderer", in: json).first(where: { ($0["sectionIdentifier"] as? String) == "comment-item-section" || ($0["targetId"] as? String) == "comments-section" }) {
            token = YTParse.firstString("token", in: section)
        }
        if token == nil {
            for panel in YTParse.all("engagementPanelSectionListRenderer", in: json)
            where (panel["panelIdentifier"] as? String) == "engagement-panel-comments-section" {
                token = YTParse.firstString("token", in: panel)
            }
        }
        let commentCount = (YTParse.first("commentsEntryPointHeaderRenderer", in: json) as? [String: Any]).flatMap { YTParse.text($0["commentCount"]) }

        let video = Video(id: id, title: title, channel: channel?.name ?? "", channelId: channel?.id, channelAvatar: channel?.avatar,
                          views: views, published: date)
        return VideoDetails(video: video, description: description, views: views, date: date, likes: likes, channel: channel,
                            chapters: chapters, related: related, commentsToken: token, commentCount: commentCount)
    }

    func comments(_ token: String) async throws -> (items: [Comment], next: String?) {
        let json = try await post("next", ["continuation": token])
        var items: [Comment] = []
        if let mutations = YTParse.dig(json, "frameworkUpdates", "entityBatchUpdate", "mutations") as? [[String: Any]] {
            for m in mutations {
                guard let p = YTParse.dig(m, "payload", "commentEntityPayload") as? [String: Any] else { continue }
                items.append(Comment(
                    id: (YTParse.dig(p, "properties", "commentId") as? String) ?? UUID().uuidString,
                    author: (YTParse.dig(p, "author", "displayName") as? String) ?? "",
                    avatar: YTParse.dig(p, "author", "avatarThumbnailUrl") as? String,
                    text: (YTParse.dig(p, "properties", "content", "content") as? String) ?? "",
                    likes: (YTParse.dig(p, "toolbar", "likeCountNotliked") as? String) ?? "",
                    published: (YTParse.dig(p, "properties", "publishedTime") as? String) ?? "",
                    replies: (YTParse.dig(p, "toolbar", "replyCount") as? String) ?? ""))
            }
        }
        if items.isEmpty {
            for c in YTParse.all("commentRenderer", in: json) {
                items.append(Comment(
                    id: (c["commentId"] as? String) ?? UUID().uuidString,
                    author: YTParse.text(c["authorText"]) ?? "",
                    avatar: (YTParse.dig(c, "authorThumbnail", "thumbnails") as? [[String: Any]])?.last?["url"] as? String,
                    text: YTParse.text(c["contentText"]) ?? "",
                    likes: YTParse.text(c["voteCount"]) ?? "",
                    published: YTParse.text(c["publishedTimeText"]) ?? "",
                    replies: ""))
            }
        }
        var next: String?
        for e in (json["onResponseReceivedEndpoints"] as? [[String: Any]]) ?? [] {
            let list = (YTParse.dig(e, "reloadContinuationItemsCommand", "continuationItems")
                        ?? YTParse.dig(e, "appendContinuationItemsAction", "continuationItems")) as? [[String: Any]]
            if let last = list?.last, let cir = last["continuationItemRenderer"] {
                next = YTParse.firstString("token", in: cir)
            }
        }
        return (items, next)
    }

    // MARK: Channels

    enum ChannelTab: String, CaseIterable, Identifiable {
        case videos, shorts, live
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var params: String {
            switch self {
            case .videos: return "EgZ2aWRlb3PyBgQKAjoA"
            case .shorts: return "EgZzaG9ydHPyBgUKA5oBAA=="
            case .live: return "EgdzdHJlYW1z8gYECgJ6AA=="
            }
        }
    }

    func channel(_ id: String, tab: ChannelTab = .videos, continuation: String? = nil) async throws -> ChannelPage {
        var body: [String: Any] = ["browseId": id, "params": tab.params]
        if let continuation { body = ["continuation": continuation] }
        let json = try await post("browse", body)
        var items = YTParse.videos(in: json)
        if tab == .shorts { items = items.map { var v = $0; v.isShort = true; return v } }
        let meta = YTParse.dig(json, "metadata", "channelMetadataRenderer") as? [String: Any]
        let name = (meta?["title"] as? String) ?? ""
        let avatar = YTParse.fix((YTParse.dig(meta, "avatar", "thumbnails") as? [[String: Any]])?.last?["url"] as? String)
        let subs = YTParse.firstString(containing: "subscriber", in: json["header"] ?? [String: Any]())
        let handle = YTParse.firstString(prefix: "@", in: json["header"] ?? [String: Any]())
        var banner: String?
        if let b = YTParse.first("imageBannerViewModel", in: json) {
            banner = ((YTParse.dig(b, "image", "sources") as? [[String: Any]])?.last?["url"] as? String)
        } else if let b = YTParse.dig(json, "header", "c4TabbedHeaderRenderer", "banner", "thumbnails") as? [[String: Any]] {
            banner = b.last?["url"] as? String
        }
        items = items.map { v in
            var v = v
            if v.channel.isEmpty { v.channel = name }
            if v.channelId == nil { v.channelId = id }
            if v.channelAvatar == nil { v.channelAvatar = avatar }
            return v
        }
        return ChannelPage(channel: Channel(id: id, name: name, avatar: avatar, subscribers: subs),
                           banner: YTParse.fix(banner), handle: handle,
                           description: meta?["description"] as? String,
                           videos: Page(items: items, continuation: YTParse.lastContinuation(in: json)))
    }

    /// Latest uploads from a channel via its public RSS feed (fast, no parsing of the web page).
    func latest(channel: Channel) async -> [Video] {
        guard let url = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channel.id)"),
              let result = try? await session.data(from: url) else { return [] }
        let parser = RSSParser(channel: channel)
        return parser.parse(result.0)
    }
}

// MARK: - RSS

private final class RSSParser: NSObject, XMLParserDelegate {
    let channel: Channel
    private var items: [Video] = []
    private var current: [String: String]?
    private var text = ""
    private static let iso = ISO8601DateFormatter()
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    init(channel: Channel) { self.channel = channel }

    func parse(_ data: Data) -> [Video] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        if name == "entry" { current = [:] }
        if name == "media:statistics", let v = attributes["views"] { current?["views"] = v }
        if name == "link", let href = attributes["href"], href.contains("/shorts/") { current?["short"] = "1" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard current != nil else { return }
        switch name {
        case "yt:videoId": current?["id"] = text
        case "title": current?["title"] = text
        case "published": current?["published"] = text
        case "entry":
            if let c = current, let id = c["id"] {
                var published: String?
                if let p = c["published"], let date = RSSParser.iso.date(from: p) {
                    published = RSSParser.relative.localizedString(for: date, relativeTo: Date())
                }
                var views: String?
                if let v = c["views"], let n = Int(v) { views = compactCount(n) + " views" }
                items.append(Video(id: id, title: c["title"] ?? "", channel: channel.name, channelId: channel.id,
                                   channelAvatar: channel.avatar, views: views, published: published, isShort: c["short"] != nil))
            }
            current = nil
        default: break
        }
    }
}

func compactCount(_ n: Int) -> String {
    switch n {
    case 1_000_000_000...: return String(format: "%.1fB", Double(n) / 1e9).replacingOccurrences(of: ".0", with: "")
    case 1_000_000...: return String(format: "%.1fM", Double(n) / 1e6).replacingOccurrences(of: ".0", with: "")
    case 1_000...: return String(format: "%.1fK", Double(n) / 1e3).replacingOccurrences(of: ".0", with: "")
    default: return "\(n)"
    }
}

// MARK: - JSON helpers

/// YouTube's JSON changes shape often, so instead of hard-coding long paths we walk the
/// whole tree and pick up any known video "renderer" wherever it appears.
enum YTParse {
    static func text(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        guard let d = any as? [String: Any] else { return nil }
        if let s = d["simpleText"] as? String { return s }
        if let runs = d["runs"] as? [[String: Any]] { return runs.compactMap { $0["text"] as? String }.joined() }
        if let c = d["content"] as? String { return c }
        return nil
    }

    static func dig(_ any: Any?, _ path: String...) -> Any? {
        var cur = any
        for key in path {
            if let i = Int(key), let a = cur as? [Any] {
                guard i < a.count else { return nil }
                cur = a[i]
            } else if let d = cur as? [String: Any] {
                cur = d[key]
            } else {
                return nil
            }
        }
        return cur
    }

    static func fix(_ url: String?) -> String? {
        guard let url else { return nil }
        return url.hasPrefix("//") ? "https:" + url : url
    }

    /// First value stored under `key` anywhere in the tree (depth-first).
    static func first(_ key: String, in node: Any) -> Any? {
        if let d = node as? [String: Any] {
            if let v = d[key] { return v }
            for v in d.values { if let f = first(key, in: v) { return f } }
        } else if let a = node as? [Any] {
            for v in a { if let f = first(key, in: v) { return f } }
        }
        return nil
    }

    static func firstString(_ key: String, in node: Any) -> String? {
        if let d = node as? [String: Any] {
            if let s = d[key] as? String { return s }
            for v in d.values { if let f = firstString(key, in: v) { return f } }
        } else if let a = node as? [Any] {
            for v in a { if let f = firstString(key, in: v) { return f } }
        }
        return nil
    }

    static func firstString(containing needle: String, in node: Any) -> String? {
        if let s = node as? String { return s.lowercased().contains(needle) && s.count < 40 ? s : nil }
        if let d = node as? [String: Any] {
            for v in d.values { if let f = firstString(containing: needle, in: v) { return f } }
        } else if let a = node as? [Any] {
            for v in a { if let f = firstString(containing: needle, in: v) { return f } }
        }
        return nil
    }

    static func firstString(prefix: String, in node: Any) -> String? {
        if let s = node as? String { return s.hasPrefix(prefix) && !s.contains(" ") && s.count > 1 ? s : nil }
        if let d = node as? [String: Any] {
            for v in d.values { if let f = firstString(prefix: prefix, in: v) { return f } }
        } else if let a = node as? [Any] {
            for v in a { if let f = firstString(prefix: prefix, in: v) { return f } }
        }
        return nil
    }

    /// Every dictionary stored under `key`, in document order.
    static func all(_ key: String, in node: Any) -> [[String: Any]] {
        var out: [[String: Any]] = []
        func walk(_ n: Any) {
            if let d = n as? [String: Any] {
                for (k, v) in d {
                    if k == key, let vd = v as? [String: Any] { out.append(vd) }
                    walk(v)
                }
            } else if let a = n as? [Any] {
                for v in a { walk(v) }
            }
        }
        walk(node)
        return out
    }

    static func lastContinuation(in json: Any) -> String? {
        var token: String?
        func walk(_ n: Any) {
            if let d = n as? [String: Any] {
                if let c = d["continuationCommand"] as? [String: Any], let t = c["token"] as? String { token = t }
                if let c = d["nextContinuationData"] as? [String: Any], let t = c["continuation"] as? String { token = t }
                for (k, v) in d where k != "continuationCommand" { walk(v) }
            } else if let a = n as? [Any] {
                for v in a { walk(v) }
            }
        }
        walk(json)
        return token
    }

    private static let skipKeys: Set<String> = ["adSlotRenderer", "promotedSparklesWebRenderer", "searchPyvRenderer", "playlistRenderer", "radioRenderer", "movieRenderer"]

    static func videos(in root: Any) -> [Video] {
        var out: [Video] = []
        var seen = Set<String>()
        func add(_ v: Video?) {
            guard let v, !v.id.isEmpty, !v.title.isEmpty, seen.insert(v.id).inserted else { return }
            out.append(v)
        }
        func walk(_ node: Any) {
            if let d = node as? [String: Any] {
                for (k, v) in d {
                    if skipKeys.contains(k) { continue }
                    guard let vd = v as? [String: Any] else {
                        if let a = v as? [Any] { for e in a { walk(e) } }
                        continue
                    }
                    switch k {
                    case "videoRenderer", "compactVideoRenderer", "gridVideoRenderer", "videoWithContextRenderer":
                        add(video(vd))
                    case "reelItemRenderer":
                        add(reel(vd))
                    case "shortsLockupViewModel":
                        add(shortsLockup(vd))
                    case "lockupViewModel":
                        add(lockup(vd))
                    default:
                        walk(vd)
                    }
                }
            } else if let a = node as? [Any] {
                for e in a { walk(e) }
            }
        }
        walk(root)
        return out
    }

    private static func lastURL(_ list: Any?) -> String? {
        fix((list as? [[String: Any]])?.last?["url"] as? String)
    }

    static func video(_ d: [String: Any]) -> Video? {
        guard let id = d["videoId"] as? String else { return nil }
        let owner = d["ownerText"] ?? d["longBylineText"] ?? d["shortBylineText"]
        let channelId = dig(owner, "runs", "0", "navigationEndpoint", "browseEndpoint", "browseId") as? String
        let avatar = lastURL(dig(d, "channelThumbnailSupportedRenderers", "channelThumbnailWithLinkRenderer", "thumbnail", "thumbnails"))
            ?? lastURL(dig(d, "channelThumbnail", "thumbnails"))
        var duration = text(d["lengthText"])
        var live = false
        for o in (d["thumbnailOverlays"] as? [[String: Any]]) ?? [] {
            if let t = o["thumbnailOverlayTimeStatusRenderer"] as? [String: Any] {
                if (t["style"] as? String) == "LIVE" { live = true } else if duration == nil { duration = text(t["text"]) }
            }
        }
        if let badges = d["badges"] as? [[String: Any]],
           badges.contains(where: { (dig($0, "metadataBadgeRenderer", "style") as? String) == "BADGE_STYLE_TYPE_LIVE_NOW" }) {
            live = true
        }
        let isShort = dig(d, "navigationEndpoint", "reelWatchEndpoint") != nil
        return Video(id: id,
                     title: text(d["title"]) ?? text(d["headline"]) ?? "",
                     channel: text(owner) ?? "",
                     channelId: channelId,
                     channelAvatar: avatar,
                     thumbnail: lastURL(dig(d, "thumbnail", "thumbnails")),
                     duration: live ? nil : duration,
                     views: text(d["shortViewCountText"]) ?? text(d["viewCountText"]),
                     published: text(d["publishedTimeText"]),
                     isLive: live,
                     isShort: isShort)
    }

    static func reel(_ d: [String: Any]) -> Video? {
        guard let id = d["videoId"] as? String else { return nil }
        return Video(id: id, title: text(d["headline"]) ?? "", thumbnail: lastURL(dig(d, "thumbnail", "thumbnails")),
                     views: text(d["viewCountText"]), isShort: true)
    }

    static func shortsLockup(_ d: [String: Any]) -> Video? {
        guard let id = (dig(d, "onTap", "innertubeCommand", "reelWatchEndpoint", "videoId") as? String)
                ?? (firstString("videoId", in: d)) else { return nil }
        return Video(id: id,
                     title: (dig(d, "overlayMetadata", "primaryText", "content") as? String) ?? "",
                     thumbnail: fix((dig(d, "thumbnail", "sources") as? [[String: Any]])?.first?["url"] as? String),
                     views: dig(d, "overlayMetadata", "secondaryText", "content") as? String,
                     isShort: true)
    }

    static func lockup(_ d: [String: Any]) -> Video? {
        guard let id = d["contentId"] as? String,
              let type = d["contentType"] as? String, type.contains("VIDEO") else { return nil }
        let meta = dig(d, "metadata", "lockupMetadataViewModel") as? [String: Any]
        var parts: [String] = []
        if let rows = dig(meta, "metadata", "contentMetadataViewModel", "metadataRows") as? [[String: Any]] {
            for r in rows {
                for p in (r["metadataParts"] as? [[String: Any]]) ?? [] {
                    if let t = text(p["text"]), !t.isEmpty { parts.append(t) }
                }
            }
        }
        var duration: String?
        var live = false
        if let badge = first("thumbnailBadgeViewModel", in: d) as? [String: Any] {
            let t = (badge["text"] as? String) ?? ""
            if t.uppercased() == "LIVE" { live = true } else { duration = t }
        }
        let image = first("thumbnailViewModel", in: d)
        let thumb = (dig(image, "image", "sources") as? [[String: Any]])?.last?["url"] as? String
        let avatarSources = first("avatarViewModel", in: meta ?? [String: Any]())
        let avatar = (dig(avatarSources, "image", "sources") as? [[String: Any]])?.last?["url"] as? String
        let channelId = firstString(prefix: "UC", in: meta ?? [String: Any]()).flatMap { $0.count == 24 ? $0 : nil }
        return Video(id: id,
                     title: text(meta?["title"]) ?? "",
                     channel: parts.first ?? "",
                     channelId: channelId,
                     channelAvatar: fix(avatar),
                     thumbnail: fix(thumb),
                     duration: duration,
                     views: parts.count > 1 ? parts[1] : nil,
                     published: parts.count > 2 ? parts[2] : nil,
                     isLive: live)
    }
}
