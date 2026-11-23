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
        TopBarPage {
            LazyVStack(spacing: t.glass ? 10 : 4) {
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
        .refreshable { await model.refresh() }
        .task { if model.items.isEmpty { await model.refresh() } }
    }

    private var greetingLine: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : (h < 18 ? "Good afternoon" : "Good evening")
    }

    private var greetingHeader: some View {
        HStack(alignment: .top) {
            Greeting(line1: greetingLine, line2: Calendar.current.component(.hour, from: Date()) >= 18 ? "What's on tonight?" : "What are we watching?")
            Spacer(minLength: 110)
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
            Color.clear.frame(width: 100, height: 1)
        }
        .font(.system(size: 20))
        .foregroundStyle(t.ink)
        .padding(.horizontal, 14)
        .frame(height: 48)
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
