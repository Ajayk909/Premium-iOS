import SwiftUI

struct ChannelView: View {
    var channelID: String
    var name: String
    @Environment(\.theme) private var t
    @Environment(\.dismiss) private var dismiss
    @State private var page: ChannelPage?
    @State private var tab: InnerTube.ChannelTab = .videos
    @State private var items: [Video] = []
    @State private var continuation: String?
    @State private var loading = false
    @State private var showAbout = false
    var lib = Library.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                banner
                info
                tabs
                if loading && items.isEmpty { LoadingDots() }
                if tab == .shorts {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(items) { s in
                            Button { AppState.shared.openShorts(items, at: s.id) } label: { ShortTile(video: s, width: (UIScreen.main.bounds.width - 42) / 2) }
                                .buttonStyle(PressStyle())
                                .onAppear { if s.id == items.last?.id { Task { await more() } } }
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    ForEach(items) { v in
                        VideoCard(video: v)
                            .onAppear { if v.id == items.last?.id { Task { await more() } } }
                    }
                }
                if !loading && items.isEmpty && page != nil {
                    EmptyState(icon: "film", title: "Nothing here", message: "This channel has no \(tab.title.lowercased()) yet.")
                }
            }
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            GlassIcon(system: "chevron.left") { dismiss() }.padding(.leading, 16).padding(.top, 4)
        }
        .task { if page == nil { await load() } }
    }

    private var banner: some View {
        ZStack {
            if let b = page?.banner, let u = URL(string: b) {
                RemoteImage(urls: [u])
            } else {
                LinearGradient(colors: [Color(hex: 0x9B8CFF), Color(hex: 0x6FD3FF)], startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.5)
            }
        }
        .frame(height: 190)
        .frame(maxWidth: .infinity)
        .clipped()
        .mask(LinearGradient(colors: [.black, .black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
    }

    private var info: some View {
        let channel = page?.channel ?? Channel(id: channelID, name: name)
        let subscribed = lib.isSubscribed(channelID)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Avatar(url: channel.avatar, name: channel.name, size: 72)
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2))
                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.name.isEmpty ? name : channel.name).font(.system(size: 24, weight: .bold)).foregroundStyle(t.ink).lineLimit(2)
                    Text([page?.handle, channel.subscribers].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(t.ink2)
                }
            }
            if let d = page?.description, !d.isEmpty {
                Button { withAnimation(Motion.spring) { showAbout.toggle() } } label: {
                    Text(d).font(.system(size: 13.5)).foregroundStyle(t.ink2).lineLimit(showAbout ? nil : 2).multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }
            Button {
                withAnimation(Motion.spring) { lib.toggleSubscribe(channel) }
            } label: {
                Text(subscribed ? "Subscribed" : "Subscribe")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(subscribed ? t.ink : t.onSubscribe)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background { if !subscribed { Capsule().fill(t.subscribe) } }
                    .modifier(SubSurface(on: subscribed))
            }
            .buttonStyle(PressStyle())
            .disabled(page == nil)
        }
        .padding(.horizontal, 20)
        .padding(.top, -40)
    }

    private var tabs: some View {
        HStack(spacing: 8) {
            ForEach(InnerTube.ChannelTab.allCases) { tb in
                Chip(title: tb.title, selected: tab == tb) {
                    guard tab != tb else { return }
                    tab = tb
                    items = []
                    Task { await load() }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    @MainActor
    private func load() async {
        loading = true
        if let p = try? await InnerTube.shared.channel(channelID, tab: tab) {
            if page == nil || tab == .videos { page = p }
            items = p.videos.items
            continuation = p.videos.continuation
            lib.updateChannel(p.channel)
        }
        loading = false
    }

    @MainActor
    private func more() async {
        guard let c = continuation, !loading else { return }
        loading = true
        if let p = try? await InnerTube.shared.channel(channelID, tab: tab, continuation: c) {
            let ids = Set(items.map(\.id))
            items += p.videos.items.filter { !ids.contains($0.id) }.map { v in
                var v = v
                if v.channel.isEmpty { v.channel = page?.channel.name ?? name }
                v.channelAvatar = v.channelAvatar ?? page?.channel.avatar
                return v
            }
            continuation = p.videos.continuation
        } else {
            continuation = nil
        }
        loading = false
    }
}

private struct SubSurface: ViewModifier {
    var on: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if on { content.surface(22) } else { content }
    }
}
