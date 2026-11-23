import SwiftUI
import AVFoundation
import Observation

/// Each Short gets its own small player so the next one can load while you watch.
@Observable
final class ShortPlayer {
    let player = AVPlayer()
    var ready = false
    var progress: Double = 0
    @ObservationIgnored private var loadedID: String?
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    init() {
        player.isMuted = false
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] t in
            guard let self, let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 else { return }
            self.progress = t.seconds / d
        }
    }

    func prepare(_ id: String) {
        guard loadedID != id else { return }
        loadedID = id
        ready = false
        Task { @MainActor in
            guard let item = try? await Streams.item(for: id, audioOnly: false, maxHeight: 1920), self.loadedID == id else { return }
            self.player.replaceCurrentItem(with: item)
            if let o = self.endObserver { NotificationCenter.default.removeObserver(o) }
            self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                self?.player.seek(to: .zero)
                self?.player.play()
            }
            self.ready = true
        }
    }

    func play() { player.play() }
    func pause() { player.pause() }
}

/// Keeps a few Short players alive (current, previous, next two) without touching view state.
final class ShortPlayerPool {
    private var players: [String: ShortPlayer] = [:]

    func get(_ id: String) -> ShortPlayer {
        if let p = players[id] { return p }
        let p = ShortPlayer()
        players[id] = p
        return p
    }

    func trim(keep: Set<String>) {
        for (k, p) in players where !keep.contains(k) {
            p.pause()
            p.player.replaceCurrentItem(with: nil)
            players[k] = nil
        }
    }

    func pauseAll() { players.values.forEach { $0.pause() } }
}

final class ShortLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct ShortSurface: UIViewRepresentable {
    var player: AVPlayer
    func makeUIView(context: Context) -> ShortLayerView {
        let v = ShortLayerView()
        v.backgroundColor = .black
        v.playerLayer.videoGravity = .resizeAspectFill
        v.playerLayer.player = player
        return v
    }
    func updateUIView(_ v: ShortLayerView, context: Context) { v.playerLayer.player = player }
}

@Observable
final class ShortsFeed {
    var items: [Video] = []
    var mode = 0
    @ObservationIgnored private var continuation: String?
    @ObservationIgnored private var seeds = ["#shorts", "funny #shorts", "music #shorts", "gaming #shorts", "food #shorts", "tech #shorts", "satisfying #shorts", "travel #shorts"]
    @ObservationIgnored private var loading = false

    @MainActor
    func start(with list: [Video], at id: String?) async {
        if !list.isEmpty {
            var l = list
            if let id, let i = l.firstIndex(where: { $0.id == id }) { l = Array(l[i...]) + Array(l[..<i]) }
            items = l
            continuation = nil
            await more()
        } else if items.isEmpty {
            await more()
        }
    }

    @MainActor
    func reload() async {
        items = []
        continuation = nil
        await more()
    }

    @MainActor
    func more() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let ids = Set(items.map(\.id))
        if mode == 1 {
            let subs = Library.shared.d.subscriptions
            guard items.isEmpty, !subs.isEmpty else { return }
            let found = await withTaskGroup(of: [Video].self) { g -> [Video] in
                for c in subs.prefix(20) { g.addTask { await InnerTube.shared.latest(channel: c).filter { $0.isShort } } }
                var all: [Video] = []
                for await l in g { all += l }
                return all
            }
            items = found.shuffled()
            return
        }
        do {
            let page: Page
            if let c = continuation {
                page = try await InnerTube.shared.search("", continuation: c)
            } else {
                page = try await InnerTube.shared.search(seeds.randomElement() ?? "#shorts", filter: .shorts)
            }
            continuation = page.continuation
            items += page.items.filter { !ids.contains($0.id) && AppSettings.shared.allowed($0) }.map { var v = $0; v.isShort = true; return v }
        } catch {}
    }
}

struct ShortsView: View {
    @Environment(\.theme) private var t
    @State private var feed = ShortsFeed()
    @State private var currentID: String?
    @State private var pool = ShortPlayerPool()
    var app = AppState.shared
    var mainPlayer = PlayerModel.shared

    private var active: Bool { app.tab == .shorts && !mainPlayer.expanded }

    var body: some View {
        GeometryReader { g in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(feed.items) { v in
                        ShortCell(video: v, player: player(for: v.id), isCurrent: v.id == currentID && active)
                            .frame(width: g.size.width, height: g.size.height)
                            .id(v.id)
                            .onAppear {
                                if let i = feed.items.firstIndex(where: { $0.id == v.id }), i >= feed.items.count - 3 {
                                    Task { await feed.more() }
                                }
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentID)
            .scrollIndicators(.hidden)
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .top) { topBar }
        .overlay { if feed.items.isEmpty { ProgressView().tint(.white) } }
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.colorScheme, .dark)
        .task { await feed.start(with: [], at: nil) }
        .onChange(of: app.shortsStartID) { _, id in
            guard let id else { return }
            let list = app.shortsStart
            app.shortsStartID = nil
            Task {
                await feed.start(with: list, at: id)
                currentID = id
            }
        }
        .onChange(of: feed.items.first?.id) { _, first in if currentID == nil { currentID = first } }
        .onChange(of: currentID) { _, id in preload(around: id) }
        .onChange(of: active) { _, on in
            if !on { pool.pauseAll() }
        }
    }

    private func player(for id: String) -> ShortPlayer { pool.get(id) }

    private func preload(around id: String?) {
        guard let id, let i = feed.items.firstIndex(where: { $0.id == id }) else { return }
        let keep = Set(feed.items[max(0, i - 1)...min(feed.items.count - 1, i + 2)].map(\.id))
        pool.trim(keep: keep)
        for k in keep { pool.get(k).prepare(k) }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(Array(["For you", "Subscriptions"].enumerated()), id: \.offset) { i, title in
                    Button {
                        guard feed.mode != i else { return }
                        feed.mode = i
                        currentID = nil
                        Task { await feed.reload() }
                    } label: {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(feed.mode == i ? Color(hex: 0x1C1D24) : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background { if feed.mode == i { Capsule().fill(.white) } }
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(4)
            .background(.ultraThinMaterial.opacity(0.7), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
            Spacer()
            Button { AppState.shared.push(.search(nil)) } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial.opacity(0.7), in: Circle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }
}

struct ShortCell: View {
    var video: Video
    var player: ShortPlayer
    var isCurrent: Bool
    @State private var details: VideoDetails?
    @State private var showComments = false
    @State private var paused = false
    var lib = Library.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            RemoteImage(urls: [video.thumbURL].compactMap { $0 })
                .blur(radius: player.ready ? 0 : 8)
            ShortSurface(player: player.player).opacity(player.ready ? 1 : 0)
                .onTapGesture {
                    paused.toggle()
                    paused ? player.pause() : player.play()
                }
            if paused {
                Image(systemName: "play.fill").font(.system(size: 50)).foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
            HStack(alignment: .bottom, spacing: 12) {
                info
                actions
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 118)
            GeometryReader { g in
                Capsule().fill(.white).frame(width: g.size.width * player.progress, height: 2)
            }
            .frame(height: 2)
            .background(.white.opacity(0.25))
            .padding(.horizontal, 16)
            .padding(.bottom, 104)
        }
        .clipped()
        .onChange(of: isCurrent) { _, on in on ? start() : player.pause() }
        .onChange(of: player.ready) { _, r in if r && isCurrent { start() } }
        .onAppear { if isCurrent { start() } }
        .sheet(isPresented: $showComments) {
            ShortComments(token: details?.commentsToken).presentationDetents([.medium, .large])
        }
    }

    private func start() {
        paused = false
        player.prepare(video.id)
        player.play()
        Library.shared.addHistory(video)
        if details == nil {
            Task { @MainActor in details = try? await InnerTube.shared.details(video.id) }
        }
    }

    private var channel: Channel? { details?.channel }

    private var info: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Avatar(url: channel?.avatar, name: channel?.name ?? video.channel, size: 34)
                Text(channel.map { $0.name } ?? video.channel).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                if let c = channel {
                    let on = lib.isSubscribed(c.id)
                    Button { lib.toggleSubscribe(c) } label: {
                        Text(on ? "Subscribed" : "Subscribe")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(on ? .white : Color(hex: 0x1C1D24))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(on ? Color.white.opacity(0.2) : .white, in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .onTapGesture {
                if let c = channel { AppState.shared.select(.home); AppState.shared.push(.channel(id: c.id, name: c.name)) }
            }
            Text(video.title.isEmpty ? (details?.video.title ?? "") : video.title)
                .font(.system(size: 15))
                .lineLimit(3)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        VStack(spacing: 16) {
            action(lib.isLiked(video.id) ? "hand.thumbsup.fill" : "hand.thumbsup", details?.likes ?? "Like") { lib.toggleLike(video) }
            action(lib.isDisliked(video.id) ? "hand.thumbsdown.fill" : "hand.thumbsdown", "Dislike") { lib.toggleDislike(video) }
            action("bubble.left", details?.commentCount ?? "Comments") { showComments = true }
            ShareLink(item: video.shareURL) { actionLabel("arrowshape.turn.up.right", "Share") }
            action(lib.inWatchLater(video.id) ? "bookmark.fill" : "bookmark", "Save") { lib.toggleWatchLater(video) }
        }
    }

    private func action(_ icon: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { actionLabel(icon, label) }.buttonStyle(PressStyle())
    }

    private func actionLabel(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial.opacity(0.6), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            Text(label).font(.system(size: 11, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(width: 60)
    }
}

private struct ShortComments: View {
    var token: String?
    @State private var items: [Comment] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("Comments").font(.system(size: 20, weight: .bold)).padding(.bottom, 4)
                if token == nil { Text("Comments are off or still loading.").foregroundStyle(.secondary) }
                ForEach(items) { c in
                    HStack(alignment: .top, spacing: 10) {
                        Avatar(url: c.avatar, name: c.author, size: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.author).font(.system(size: 12)).foregroundStyle(.secondary)
                            Text(c.text).font(.system(size: 14.5))
                        }
                    }
                }
            }
            .padding(20)
        }
        .presentationBackground(.ultraThinMaterial)
        .task {
            guard let token, let r = try? await InnerTube.shared.comments(token) else { return }
            items = r.items
        }
    }
}
