import SwiftUI
import Observation

@Observable
final class HomeModel {
    static let chips = ["All", "Music", "Gaming", "Podcasts", "Live", "News", "Tech", "Cooking", "Sports"]
    private static let starterSeeds = ["trending today", "new music video", "tech review", "gaming highlights",
                                       "podcast clips", "travel vlog", "cooking recipe", "science explained", "comedy sketch"]

    var chip = "All"
    var items: [Video] = []
    var shorts: [Video] = []
    var loading = false
    var failed = false
    @ObservationIgnored private var continuation: String?
    @ObservationIgnored private var seeds: [String] = []
    @ObservationIgnored private var loadingMore = false

    private var hideShorts: Bool { AppSettings.shared.d.hideShortsOnHome }

    private func keep(_ list: [Video]) -> [Video] {
        let existing = Set(items.map(\.id))
        return list.filter { !existing.contains($0.id) && AppSettings.shared.allowed($0) && !$0.isShort }
    }

    @MainActor
    func refresh() async {
        loading = items.isEmpty
        failed = false
        continuation = nil
        do {
            if chip == "All" {
                try await loadMixed()
            } else {
                let page = try await InnerTube.shared.search(chip == "Live" ? "live now" : chip.lowercased(), filter: chip == "Live" ? .live : .none)
                items = []
                items = keep(page.items)
                continuation = page.continuation
            }
        } catch {
            failed = items.isEmpty
        }
        loading = false
    }

    @MainActor
    private func loadMixed() async throws {
        let lib = Library.shared.d
        let subs = Array(lib.subscriptions.shuffled().prefix(8))
        var pool = Set<String>()
        lib.history.prefix(30).map(\.channel).filter { !$0.isEmpty }.forEach { pool.insert($0) }
        subs.map(\.name).forEach { pool.insert($0) }
        var s = Array(pool).shuffled()
        if s.count < 4 { s += HomeModel.starterSeeds.shuffled() }
        seeds = s

        async let feeds: [Video] = withTaskGroup(of: [Video].self) { group in
            for c in subs { group.addTask { Array(await InnerTube.shared.latest(channel: c).prefix(3)) } }
            var all: [Video] = []
            for await list in group { all += list }
            return all
        }
        let first = seeds.removeFirst()
        async let pageA = InnerTube.shared.search(first)
        async let shortsPage = try? InnerTube.shared.search("#shorts", filter: .shorts)

        let fromSubs = await feeds
        let a = try await pageA
        continuation = a.continuation
        var mixed = fromSubs.filter { !$0.isShort }.shuffled()
        var searchItems = a.items.filter { !$0.isShort }
        var merged: [Video] = []
        while !mixed.isEmpty || !searchItems.isEmpty {
            if !mixed.isEmpty { merged.append(mixed.removeFirst()) }
            if !searchItems.isEmpty { merged.append(searchItems.removeFirst()) }
            if !searchItems.isEmpty { merged.append(searchItems.removeFirst()) }
        }
        items = []
        items = keep(merged)
        shorts = hideShorts ? [] : Array(((await shortsPage)?.items ?? []).prefix(12))
    }

    @MainActor
    func loadMore() async {
        guard !loadingMore, !loading else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            if let c = continuation {
                let page = try await InnerTube.shared.search("", continuation: c)
                continuation = page.continuation
                items += keep(page.items)
            } else if chip == "All", !seeds.isEmpty {
                let page = try await InnerTube.shared.search(seeds.removeFirst())
                continuation = page.continuation
                items += keep(page.items.shuffled())
            }
        } catch {}
    }
}

struct HomeView: View {
    @Environment(\.theme) private var t
    @State private var model = HomeModel()
    var lib = Library.shared

    var body: some View {
        ScrollView {
            LazyVStack(spacing: t.glass ? 14 : 4) {
                if t.usesGreeting { greetingHeader } else { classicHeader }
                if t.usesGreeting { widgets }
                chips
                if model.loading {
                    LoadingDots()
                } else if model.failed {
                    EmptyState(icon: "wifi.exclamationmark", title: "Couldn't load your feed", message: "Pull down to try again.")
                }
                ForEach(Array(model.items.enumerated()), id: \.element.id) { i, v in
                    VideoCard(video: v)
                        .onAppear { if i >= model.items.count - 4 { Task { await model.loadMore() } } }
                    if i == 3 && !model.shorts.isEmpty { shortsShelf }
                }
            }
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.refresh() }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task { if model.items.isEmpty { await model.refresh() } }
    }

    private var greetingLine: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : (h < 18 ? "Good afternoon" : "Good evening")
    }

    private var greetingHeader: some View {
        HStack(alignment: .top) {
            Greeting(line1: greetingLine, line2: "What's on tonight?")
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                GlassIcon(system: "magnifyingglass") { AppState.shared.push(.search(nil)) }
                Button { AppState.shared.push(.settings) } label: {
                    Image(systemName: "person.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(t.ink)
                        .frame(width: 38, height: 38)
                        .surface(19)
                }
                .buttonStyle(PressStyle())
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var classicHeader: some View {
        HStack(spacing: 18) {
            HStack(spacing: 4) {
                Image(systemName: "play.rectangle.fill").font(.system(size: 24)).foregroundStyle(.red)
                Text("Premium").font(.system(size: 20, weight: .bold)).tracking(-0.8).foregroundStyle(t.ink)
            }
            Spacer()
            Button { AppState.shared.showCast = true } label: { Image(systemName: "tv") }
            Button { AppState.shared.push(.search(nil)) } label: { Image(systemName: "magnifyingglass") }
            Button { AppState.shared.push(.settings) } label: { Image(systemName: "person.crop.circle") }
        }
        .font(.system(size: 20))
        .foregroundStyle(t.ink)
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    // MARK: Widgets

    private var widgets: some View {
        let continueVideo = lib.d.history.first { lib.progress($0.id) > 5 } ?? lib.d.history.first
        let player = PlayerModel.shared
        let upNext = player.queue.first ?? lib.d.watchLater.first
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                widgetVideo(label: "Continue watching", video: continueVideo, playing: continueVideo?.id == player.current?.id, emptyText: "Videos you watch show up here")
                widgetVideo(label: player.queue.isEmpty ? "Watch later" : "Up next · Queue \(player.queue.count)", video: upNext, playing: false, emptyText: "Save videos with •••")
            }
            HStack(spacing: 12) {
                weekWidget
                castWidget
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private func widgetVideo(label: String, video: Video?, playing: Bool, emptyText: String) -> some View {
        Button { if let video { PlayerModel.shared.play(video) } } label: {
            VStack(alignment: .leading, spacing: 8) {
                CardLabel(text: label).lineLimit(1)
                if let video {
                    Thumbnail(video: video, radius: 12)
                    Text(video.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(t.ink).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                } else {
                    Spacer()
                    Text(emptyText).font(.system(size: 13)).foregroundStyle(t.ink2).multilineTextAlignment(.leading)
                    Spacer()
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 176)
            .surface(26)
            .rainbowEdge(26, on: playing)
        }
        .buttonStyle(PressStyle())
    }

    private var weekWidget: some View {
        let days = lib.lastSevenDays
        let maxS = max(days.map(\.seconds).max() ?? 1, 1)
        return Button { AppState.shared.push(.stats) } label: {
            VStack(alignment: .leading, spacing: 6) {
                CardLabel(text: "This week")
                Text(formatDuration(lib.weekTotal)).font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(t.ink)
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(d.today ? t.accent : t.ink.opacity(0.13))
                            .frame(height: max(6, 32 * d.seconds / maxS))
                    }
                }
                .frame(height: 32, alignment: .bottom)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 128)
            .surface(26)
        }
        .buttonStyle(PressStyle())
    }

    private var castWidget: some View {
        let roku = Roku.shared
        return Button { AppState.shared.showCast = true } label: {
            VStack(alignment: .leading, spacing: 5) {
                CardLabel(text: "Cast")
                Text(roku.current?.name ?? "Roku TV")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(t.ink).lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    Circle().fill(roku.current == nil ? t.ink3 : t.success).frame(width: 7, height: 7)
                    Text(roku.current == nil ? "Not set up" : "Ready").font(.system(size: 12.5)).foregroundStyle(t.ink2)
                }
                Spacer(minLength: 0)
                Label(roku.current == nil ? "Set up" : "Remote", systemImage: "tv")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(t.ink)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .surface(16, strong: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 128)
            .surface(26)
        }
        .buttonStyle(PressStyle())
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(HomeModel.chips, id: \.self) { c in
                    Chip(title: c, selected: model.chip == c) {
                        guard model.chip != c else { return }
                        model.chip = c
                        model.items = []
                        Task { await model.refresh() }
                    }
                }
            }
            .padding(.horizontal, t.glass ? 20 : 12)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
    }

    private var shortsShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "play.rectangle.on.rectangle.fill").foregroundStyle(t.kind == .classic ? .red : t.ink)
                Text("Shorts").font(.system(size: 18, weight: .semibold)).foregroundStyle(t.ink)
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(model.shorts) { s in
                        Button { AppState.shared.openShorts(model.shorts, at: s.id) } label: { ShortTile(video: s) }
                            .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, 6)
    }
}

/// "Search Premium…" bar that floats above the tab bar on Home.
struct HomeSearchBar: View {
    @Environment(\.theme) private var t

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(t.ink2)
            Text("Search Premium…").foregroundStyle(t.ink3)
            Spacer()
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(t.ink)
                .frame(width: 42, height: 42)
                .background(t.dark ? Color.white.opacity(0.14) : Color.white, in: Circle())
                .rainbowCircle()
                .onTapGesture { AppState.shared.push(.search("__voice__")) }
        }
        .font(.system(size: 16))
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .frame(height: 54)
        .surface(27, strong: true)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
        .onTapGesture { AppState.shared.push(.search(nil)) }
    }
}
