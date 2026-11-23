import SwiftUI

final class ImageCache {
    static let shared: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 400
        return c
    }()
}

/// Loads the first URL that works (e.g. the sharp hq720 thumbnail, then the always-there hqdefault).
struct RemoteImage: View {
    var urls: [URL]
    var contentMode: ContentMode = .fill
    @Environment(\.theme) private var t
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(t.ink.opacity(0.08))
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: urls.first) { await load() }
    }

    private func load() async {
        for url in urls {
            if let cached = ImageCache.shared.object(forKey: url as NSURL) {
                image = cached
                return
            }
        }
        for url in urls {
            guard let result = try? await URLSession.shared.data(from: url),
                  (result.1 as? HTTPURLResponse)?.statusCode ?? 200 == 200,
                  let img = UIImage(data: result.0), img.size.width > 130 || urls.count == 1 else { continue }
            ImageCache.shared.setObject(img, forKey: url as NSURL)
            withAnimation(.easeOut(duration: 0.2)) { image = img }
            return
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
            .overlay { RemoteImage(urls: urls) }
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
                RemoteImage(urls: [u])
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
