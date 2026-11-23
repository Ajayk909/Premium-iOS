import SwiftUI
import Observation

enum Tab: String, CaseIterable, Identifiable {
    case home, shorts, subscriptions, you
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .shorts: return "Shorts"
        case .subscriptions: return "Subscriptions"
        case .you: return "You"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house"
        case .shorts: return "play.rectangle.on.rectangle"
        case .subscriptions: return "play.square.stack"
        case .you: return "person.crop.circle"
        }
    }
    var iconOn: String {
        switch self {
        case .home: return "house.fill"
        case .shorts: return "play.rectangle.on.rectangle.fill"
        case .subscriptions: return "play.square.stack.fill"
        case .you: return "person.crop.circle.fill"
        }
    }
}

enum ListKind: String, Hashable {
    case history, watchLater, liked
    var title: String {
        switch self {
        case .history: return "History"
        case .watchLater: return "Watch later"
        case .liked: return "Liked videos"
        }
    }
}

enum Route: Hashable {
    case search(String?)
    case channel(id: String, name: String)
    case list(ListKind)
    case playlist(String)
    case playlists
    case settings
    case appearance
    case stats
}

@Observable
final class AppState {
    static let shared = AppState()

    var tab: Tab = .home
    var paths: [Tab: [Route]] = [.home: [], .shorts: [], .subscriptions: [], .you: []]
    /// Video waiting for "Save to playlist".
    var saveTarget: Video?
    var showCast = false
    var shortsStart: [Video] = []
    var shortsStartID: String?

    func path(_ tab: Tab) -> Binding<[Route]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    func push(_ r: Route) {
        PlayerModel.shared.expanded = false
        paths[tab, default: []].append(r)
    }

    func select(_ t: Tab) {
        if tab == t {
            paths[t] = []
        } else {
            withAnimation(Motion.spring) { tab = t }
        }
    }

    func openShorts(_ list: [Video], at id: String) {
        shortsStart = list.filter { $0.isShort }
        shortsStartID = id
        PlayerModel.shared.pause()
        withAnimation(Motion.spring) { tab = .shorts }
    }
}
