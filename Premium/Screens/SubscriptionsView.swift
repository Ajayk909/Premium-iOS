import SwiftUI
import Observation

@Observable
final class SubsModel {
    var items: [Video] = []
    var loading = false
    var fresh: Set<String> = []
    @ObservationIgnored private var loadedFor: [String] = []

    @MainActor
    func load(force: Bool = false) async {
        let subs = Library.shared.d.subscriptions
        let ids = subs.map(\.id)
        guard force || ids != loadedFor else { return }
        loadedFor = ids
        guard !subs.isEmpty else { items = []; return }
        loading = items.isEmpty
        let all = await withTaskGroup(of: [Video].self) { g -> [Video] in
            for c in subs { g.addTask { await InnerTube.shared.latest(channel: c) } }
            var list: [Video] = []
            for await l in g { list += l }
            return list
        }
        // RSS gives ISO dates; we turned them into "2 hours ago" etc. Sort by how recent that reads.
        items = all.filter { AppSettings.shared.allowed($0) }.sorted { SubsModel.age($0.published) < SubsModel.age($1.published) }
        fresh = Set(items.filter { SubsModel.age($0.published) < 2 * 86400 }.compactMap(\.channelId))
        loading = false
    }

    static func age(_ text: String?) -> Double {
        guard let text = text?.lowercased() else { return .infinity }
        let n = Double(text.split(separator: " ").first.flatMap { Int($0) } ?? 1)
        if text.contains("second") { return n }
        if text.contains("minute") { return n * 60 }
        if text.contains("hour") { return n * 3600 }
        if text.contains("day") || text.contains("yesterday") { return n * 86400 }
        if text.contains("week") { return n * 604800 }
        if text.contains("month") { return n * 2_592_000 }
        if text.contains("year") { return n * 31_536_000 }
        return .infinity
    }
}

struct SubscriptionsView: View {
    @Environment(\.theme) private var t
    @State private var model = SubsModel()
    @State private var filter = "All"
    @State private var manage = false
    var lib = Library.shared

    private var shown: [Video] {
        switch filter {
        case "Today": return model.items.filter { SubsModel.age($0.published) < 86400 && !$0.isShort }
        case "Videos": return model.items.filter { !$0.isShort }
        case "Shorts": return model.items.filter { $0.isShort }
        case "Continue watching": return model.items.filter { lib.progress($0.id) > 5 }
        default: return model.items.filter { !$0.isShort }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                header
                if lib.d.subscriptions.isEmpty {
                    EmptyState(icon: "play.square.stack", title: "No subscriptions yet",
                               message: "Tap Subscribe on any video or channel and their new uploads show up here.")
                        .padding(.top, 40)
                } else {
                    channelRow
                    chips
                    if model.loading { LoadingDots() }
                    if filter == "Shorts" {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(shown) { s in
                                Button { AppState.shared.openShorts(shown, at: s.id) } label: { ShortTile(video: s, width: (UIScreen.main.bounds.width - 42) / 2) }
                                    .buttonStyle(PressStyle())
                            }
                        }
                        .padding(.horizontal, 16)
                    } else {
                        ForEach(shown) { v in
                            VideoRow(video: v).padding(.horizontal, t.glass ? 16 : 12)
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.load(force: true) }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: lib.d.subscriptions.count) { await model.load() }
        .sheet(isPresented: $manage) { ManageSubs().environment(\.theme, t) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            if t.usesGreeting {
                Greeting(line1: "Subscriptions", line2: model.items.isEmpty ? "\(lib.d.subscriptions.count) channels" : "\(model.items.filter { SubsModel.age($0.published) < 86400 }.count) new today")
            } else {
                Text("Subscriptions").font(.system(size: 22, weight: .bold)).foregroundStyle(t.ink)
            }
            Spacer()
            if !lib.d.subscriptions.isEmpty {
                GlassIcon(system: "slider.horizontal.3") { manage = true }.padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var channelRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(lib.d.subscriptions) { c in
                    let new = model.fresh.contains(c.id)
                    Button { AppState.shared.push(.channel(id: c.id, name: c.name)) } label: {
                        VStack(spacing: 6) {
                            Avatar(url: c.avatar, name: c.name, size: 52)
                                .padding(3)
                                .rainbowCircle(on: new, width: 2.5)
                            Text(c.name).font(.system(size: 11, weight: new ? .semibold : .medium))
                                .foregroundStyle(new ? t.ink : t.ink2).lineLimit(1)
                        }
                        .frame(width: 64)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(["All", "Today", "Videos", "Shorts", "Continue watching"], id: \.self) { c in
                    Chip(title: c, selected: filter == c) { withAnimation(Motion.spring) { filter = c } }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }
}

private struct ManageSubs: View {
    var lib = Library.shared
    var body: some View {
        NavigationStack {
            List {
                ForEach(lib.d.subscriptions) { c in
                    HStack(spacing: 12) {
                        Avatar(url: c.avatar, name: c.name, size: 36)
                        Text(c.name)
                        Spacer()
                        Button("Unsubscribe", role: .destructive) { lib.toggleSubscribe(c) }
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
            }
            .navigationTitle("\(lib.d.subscriptions.count) subscriptions")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
