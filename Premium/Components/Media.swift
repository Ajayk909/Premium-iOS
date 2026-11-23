import SwiftUI
import ImageIO

/// Downloads and decodes images off the main thread, shrunk to the size they're shown at,
/// so scrolling never waits on JPEG decoding. Requests for the same picture are shared.
actor ImageLoader {
    static let shared = ImageLoader()
    nonisolated let memory: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 120 * 1024 * 1024
        return c
    }()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache.shared
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: c)
    }()

    nonisolated static func key(_ url: URL, _ px: Int) -> NSString { "\(url.absoluteString)#\(px)" as NSString }

    nonisolated func cached(_ url: URL, maxPixel: Int) -> UIImage? {
        memory.object(forKey: Self.key(url, maxPixel))
    }

    func load(_ url: URL, maxPixel: Int) async -> UIImage? {
        let key = Self.key(url, maxPixel) as String
        if let img = memory.object(forKey: key as NSString) { return img }
        if let t = inFlight[key] { return await t.value }
        let session = self.session
        let task = Task<UIImage?, Never>.detached(priority: .userInitiated) {
            guard let r = try? await session.data(from: url),
                  (r.1 as? HTTPURLResponse)?.statusCode ?? 200 == 200 else { return nil }
            return ImageLoader.downsample(r.0, maxPixel: maxPixel)
        }
        inFlight[key] = task
        let img = await task.value
        inFlight[key] = nil
        if let img {
            memory.setObject(img, forKey: key as NSString, cost: Int(img.size.width * img.size.height * img.scale * img.scale * 4))
        }
        return img
    }

    nonisolated static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, opts) else { return nil }
        let thumbOpts = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                         kCGImageSourceShouldCacheImmediately: true,
                         kCGImageSourceCreateThumbnailWithTransform: true,
                         kCGImageSourceThumbnailMaxPixelSize: maxPixel] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Loads the first URL that works (e.g. the sharp hq720 thumbnail, then the always-there hqdefault).
struct RemoteImage: View {
    var urls: [URL]
    var contentMode: ContentMode = .fill
    /// Longest side in pixels to decode at.
    var maxPixel: Int = 720
    @Environment(\.theme) private var t
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(t.ink.opacity(0.08))
            .overlay {
                if let img = image ?? firstCached {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
            }
            .clipped()
            .task(id: urls.first) { await load() }
    }

    private var firstCached: UIImage? {
        for u in urls { if let i = ImageLoader.shared.cached(u, maxPixel: maxPixel) { return i } }
        return nil
    }

    private func load() async {
        if firstCached != nil { return }
        for (i, url) in urls.enumerated() {
            if let img = await ImageLoader.shared.load(url, maxPixel: maxPixel),
               img.size.width > 130 || i == urls.count - 1 {
                image = img
                return
            }
        }
    }
}

struct Thumbnail: View {
    @Environment(\.theme) private var t
    var video: Video
    var radius: CGFloat = 16
    var large = false
    var aspect: CGFloat = 16 / 9

    private var urls: [URL] {
        var list: [URL] = []
        if large, let u = video.largeThumbURL { list.append(u) }
        if let u = video.thumbURL { list.append(u) }
        if let u = URL(string: "https://i.ytimg.com/vi/\(video.id)/hqdefault.jpg"), !list.contains(u) { list.append(u) }
        return list
    }

    var body: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay { RemoteImage(urls: urls, maxPixel: large ? 960 : 480) }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if video.isLive {
                    badge("LIVE", bg: t.danger)
                } else if let d = video.duration, !d.isEmpty {
                    badge(d, bg: .black.opacity(0.72))
                }
            }
            .overlay(alignment: .bottom) {
                if let f = Library.shared.progressFraction(video) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.4))
                            Rectangle().fill(t.kind == .classic ? Color.red : .white).frame(width: g.size.width * f)
                        }
                    }
                    .frame(height: 3)
                    .clipShape(Capsule())
                    .padding(.horizontal, radius > 0 ? 8 : 0)
                    .padding(.bottom, radius > 0 ? 4 : 0)
                }
            }
    }

    private func badge(_ text: String, bg: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(bg, in: RoundedRectangle(cornerRadius: 5))
            .padding(7)
    }
}

struct Avatar: View {
    var url: String?
    var name: String
    var size: CGFloat = 36

    private static let palette: [Color] = [Color(hex: 0xF05E6E), Color(hex: 0x7C6CF0), Color(hex: 0x3B6FE0), Color(hex: 0x1F9A7C), Color(hex: 0xE86A4A), Color(hex: 0xFF7EB3)]

    var body: some View {
        ZStack {
            Circle().fill(Avatar.palette[name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Avatar.palette.count])
            Text(initials).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(.white)
            if let url, let u = URL(string: url) {
                RemoteImage(urls: [u], maxPixel: Int(size * 3))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}
