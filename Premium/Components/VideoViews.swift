import SwiftUI

/// Big feed card. Glass themes: a rounded glass card. Classic: edge-to-edge like the YouTube kit.
struct VideoCard: View {
    @Environment(\.theme) private var t
    var video: Video

    var body: some View {
        if t.glass { glassCard } else { classicCard }
    }

    private var glassCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { PlayerModel.shared.play(video) } label: {
                Thumbnail(video: video, radius: 18, large: true)
            }
            .buttonStyle(PressStyle())
            info
                .padding(.horizontal, 4)
                .padding(.bottom, 2)
        }
        .padding(10)
        .surface(26)
        .padding(.horizontal, 16)
    }

    private var classicCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { PlayerModel.shared.play(video) } label: {
                Thumbnail(video: video, radius: 0, large: true)
            }
            .buttonStyle(.plain)
            info.padding(12)
        }
        .padding(.bottom, 8)
    }

    private var info: some View {
        HStack(alignment: .top, spacing: 12) {
            ChannelAvatarLink(video: video, size: 36)
            Button { PlayerModel.shared.play(video) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(t.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(video.meta)
                        .font(.system(size: 12.5))
                        .foregroundStyle(t.ink2)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            VideoMenu(video: video)
        }
    }
}

/// Compact row: thumbnail on the left, text on the right.
struct VideoRow: View {
    @Environment(\.theme) private var t
    var video: Video
    var thumbWidth: CGFloat = 150
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Thumbnail(video: video, radius: t.glass ? 13 : 8)
                .frame(width: thumbWidth)
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(t.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(video.meta)
                    .font(.system(size: 12))
                    .foregroundStyle(t.ink2)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
            VideoMenu(video: video, onRemove: onRemove)
        }
        .padding(t.glass ? 8 : 0)
        .modifier(RowSurface())
        .contentShape(Rectangle())
        .onTapGesture { PlayerModel.shared.play(video) }
    }
}

private struct RowSurface: ViewModifier {
    @Environment(\.theme) private var t
    @ViewBuilder func body(content: Content) -> some View {
        if t.glass { content.surface(20) } else { content }
    }
}

/// Portrait tile for Shorts rows.
struct ShortTile: View {
    @Environment(\.theme) private var t
    var video: Video
    var width: CGFloat = 130

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(width: width, height: width * 16 / 9)
                .overlay { RemoteImage(urls: [video.thumbURL, URL(string: "https://i.ytimg.com/vi/\(video.id)/oardefault.jpg")].compactMap { $0 }) }
                .clipShape(RoundedRectangle(cornerRadius: t.glass ? 18 : 10, style: .continuous))
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: t.glass ? 18 : 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(2)
                if let v = video.views { Text(v).font(.system(size: 11)).opacity(0.85) }
            }
            .foregroundStyle(.white)
            .padding(9)
        }
        .frame(width: width)
    }
}

struct ChannelAvatarLink: View {
    var video: Video
    var size: CGFloat

    var body: some View {
        if let id = video.channelId {
            Button { AppState.shared.push(.channel(id: id, name: video.channel)) } label: {
                Avatar(url: video.channelAvatar, name: video.channel, size: size)
            }
            .buttonStyle(PressStyle())
        } else {
            Avatar(url: video.channelAvatar, name: video.channel, size: size)
        }
    }
}

/// The ••• menu on every video.
struct VideoMenu: View {
    @Environment(\.theme) private var t
    var video: Video
    var onRemove: (() -> Void)? = nil

    var body: some View {
        Menu {
            Button { PlayerModel.shared.playNext(video) } label: { Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { PlayerModel.shared.addToQueue(video) } label: { Label("Add to queue", systemImage: "text.badge.plus") }
            Button { Library.shared.toggleWatchLater(video) } label: {
                Label(Library.shared.inWatchLater(video.id) ? "Remove from Watch later" : "Save to Watch later", systemImage: "clock")
            }
            Button { AppState.shared.saveTarget = video } label: { Label("Save to playlist…", systemImage: "text.badge.plus") }
            ShareLink(item: video.shareURL) { Label("Share", systemImage: "square.and.arrow.up") }
            if Roku.shared.current != nil {
                Button { Roku.shared.cast(video.id) } label: { Label("Play on \(Roku.shared.current?.name ?? "TV")", systemImage: "tv") }
            }
            if let id = video.channelId {
                Button { AppState.shared.push(.channel(id: id, name: video.channel)) } label: { Label("Go to channel", systemImage: "person.crop.square") }
            }
            if let onRemove {
                Button(role: .destructive, action: onRemove) { Label("Remove", systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(t.ink2)
                .frame(width: 28, height: 30)
                .contentShape(Rectangle())
        }
    }
}

struct SectionHeader: View {
    @Environment(\.theme) private var t
    var title: String
    var action: String? = nil
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title).font(.system(size: 18, weight: .semibold)).foregroundStyle(t.ink)
            Spacer()
            if let action, let onTap {
                Button(action, action: onTap)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(t.ink2)
            }
        }
        .padding(.horizontal, 20)
    }
}

struct EmptyState: View {
    @Environment(\.theme) private var t
    var icon: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34, weight: .regular)).foregroundStyle(t.ink3)
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(t.ink)
            Text(message).font(.system(size: 14)).foregroundStyle(t.ink2).multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
    }
}

struct LoadingDots: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0x6FD3FF), Color(hex: 0x9B8CFF)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 8, height: 8)
                    .scaleEffect(on ? 1 : 0.5)
                    .opacity(on ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.55).repeatForever().delay(Double(i) * 0.15), value: on)
            }
        }
        .onAppear { on = true }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
