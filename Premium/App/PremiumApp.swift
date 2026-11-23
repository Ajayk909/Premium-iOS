import SwiftUI

@main
struct PremiumApp: App {
    init() {
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var app = AppState.shared
    var player = PlayerModel.shared
    var settings = AppSettings.shared
    @State private var now = Date()
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        let theme = settings.currentTheme(at: now)
        let showMini = player.current != nil && !player.expanded && app.tab != .shorts
        let bottomSpace: CGFloat = 80 + (showMini ? 76 : 0)

        ZStack(alignment: .bottom) {
            ZStack {
                ForEach(Tab.allCases) { tab in
                    NavigationStack(path: app.path(tab)) {
                        root(tab)
                            .navigationDestination(for: Route.self) { destination($0) }
                    }
                    .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tab == .shorts ? 0 : bottomSpace) }
                    .opacity(app.tab == tab ? 1 : 0)
                    .allowsHitTesting(app.tab == tab && !player.expanded)
                }
            }

            VStack(spacing: 10) {
                if showMini { MiniPlayer() }
                if !player.expanded { TabBar() }
            }
            .padding(.bottom, theme.glass ? 2 : 0)
            .animation(Motion.spring, value: showMini)

            if player.current != nil && player.expanded {
                WatchView()
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            }
        }
        .overlay(alignment: .top) {
            if let toast = player.toast {
                Toast(text: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(5)
            }
        }
        .animation(Motion.spring, value: player.expanded)
        .sheet(item: Binding(get: { app.saveTarget }, set: { app.saveTarget = $0 })) { v in
            SaveSheet(video: v).presentationDetents([.medium, .large]).environment(\.theme, theme)
        }
        .sheet(isPresented: Binding(get: { app.showCast }, set: { app.showCast = $0 })) {
            CastSheet().presentationDetents([.large]).presentationBackground(.clear).environment(\.theme, theme)
        }
        .environment(\.theme, theme)
        .preferredColorScheme(theme.dark ? .dark : .light)
        .tint(theme.ink)
        .onReceive(clock) { now = $0 }
        .task { await GoogleAccount.shared.refreshOnLaunch() }
    }

    @ViewBuilder
    private func root(_ tab: Tab) -> some View {
        switch tab {
        case .home: HomeView()
        case .shorts: ShortsView()
        case .subscriptions: SubscriptionsView()
        case .you: YouView()
        }
    }

    @ViewBuilder
    private func destination(_ r: Route) -> some View {
        switch r {
        case .search(let q): SearchView(initial: q)
        case .channel(let id, let name): ChannelView(channelID: id, name: name)
        case .list(let kind): VideoListView(kind: kind)
        case .playlist(let id): PlaylistView(playlistID: id)
        case .playlists: PlaylistsView()
        case .settings: SettingsView()
        case .appearance: AppearanceView()
        case .stats: StatsView()
        }
    }
}
