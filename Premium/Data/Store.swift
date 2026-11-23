import SwiftUI
import Observation

/// Everything the app keeps on the phone: subscriptions, history, saved lists, watch time.
struct LibraryData: Codable {
    var subscriptions: [Channel] = []
    var history: [Video] = []
    var watchLater: [Video] = []
    var liked: [Video] = []
    var disliked: [String] = []
    var playlists: [Playlist] = []
    var progress: [String: Double] = [:]
    var watchSeconds: [String: Double] = [:]
    var channelSeconds: [String: Double] = [:]
    var recentSearches: [String] = []
}

@Observable
final class Library {
    static let shared = Library()

    private(set) var d: LibraryData
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }()

    init() {
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(LibraryData.self, from: data) {
            d = decoded
        } else {
            d = LibraryData()
        }
    }

    private func save() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let data = try? JSONEncoder().encode(self.d) else { return }
            try? data.write(to: self.url, options: .atomic)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func exportData() -> Data { (try? JSONEncoder().encode(d)) ?? Data() }

    func importData(_ data: Data) -> Bool {
        guard let decoded = try? JSONDecoder().decode(LibraryData.self, from: data) else { return false }
        d = decoded
        save()
        return true
    }

    // MARK: Subscriptions
    func isSubscribed(_ id: String?) -> Bool {
        guard let id else { return false }
        return d.subscriptions.contains { $0.id == id }
    }

    func toggleSubscribe(_ c: Channel) {
        if let i = d.subscriptions.firstIndex(where: { $0.id == c.id }) {
            d.subscriptions.remove(at: i)
        } else {
            d.subscriptions.insert(c, at: 0)
        }
        save()
    }

    func updateChannel(_ c: Channel) {
        guard let i = d.subscriptions.firstIndex(where: { $0.id == c.id }) else { return }
        var merged = d.subscriptions[i]
        merged.name = c.name.isEmpty ? merged.name : c.name
        merged.avatar = c.avatar ?? merged.avatar
        merged.subscribers = c.subscribers ?? merged.subscribers
        if merged != d.subscriptions[i] { d.subscriptions[i] = merged; save() }
    }

    // MARK: History & progress
    func addHistory(_ v: Video) {
        d.history.removeAll { $0.id == v.id }
        d.history.insert(v, at: 0)
        if d.history.count > 500 { d.history.removeLast(d.history.count - 500) }
        save()
    }

    func updateVideo(_ v: Video) {
        if let i = d.history.firstIndex(where: { $0.id == v.id }) { d.history[i] = v; save() }
    }

    func clearHistory() { d.history = []; d.progress = [:]; save() }

    func removeHistory(_ id: String) { d.history.removeAll { $0.id == id }; save() }

    func progress(_ id: String) -> Double { d.progress[id] ?? 0 }

    func setProgress(_ id: String, _ seconds: Double?) {
        d.progress[id] = seconds
        save()
    }

    func progressFraction(_ v: Video) -> Double? {
        guard let p = d.progress[v.id], p > 5, let total = v.durationSeconds, total > 0 else { return nil }
        return min(1, p / Double(total))
    }

    // MARK: Watch time
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func addWatch(_ seconds: Double, channel: String?) {
        let key = Library.dayFormatter.string(from: Date())
        d.watchSeconds[key, default: 0] += seconds
        if let channel, !channel.isEmpty { d.channelSeconds[channel, default: 0] += seconds }
        save()
    }

    /// Seconds watched on each of the last 7 days, oldest first.
    var lastSevenDays: [(label: String, seconds: Double, today: Bool)] {
        let cal = Calendar.current
        let letter = DateFormatter()
        letter.dateFormat = "EEEEE"
        return (0..<7).reversed().map { back in
            let day = cal.date(byAdding: .day, value: -back, to: Date())!
            return (letter.string(from: day), d.watchSeconds[Library.dayFormatter.string(from: day)] ?? 0, back == 0)
        }
    }

    var weekTotal: Double { lastSevenDays.reduce(0) { $0 + $1.seconds } }

    var topChannels: [(String, Double)] {
        d.channelSeconds.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    // MARK: Lists
    func isLiked(_ id: String) -> Bool { d.liked.contains { $0.id == id } }
    func isDisliked(_ id: String) -> Bool { d.disliked.contains(id) }

    func toggleLike(_ v: Video) {
        if let i = d.liked.firstIndex(where: { $0.id == v.id }) { d.liked.remove(at: i) } else { d.liked.insert(v, at: 0); d.disliked.removeAll { $0 == v.id } }
        save()
    }

    func toggleDislike(_ v: Video) {
        if let i = d.disliked.firstIndex(of: v.id) { d.disliked.remove(at: i) } else { d.disliked.append(v.id); d.liked.removeAll { $0.id == v.id } }
        save()
    }

    func inWatchLater(_ id: String) -> Bool { d.watchLater.contains { $0.id == id } }

    func toggleWatchLater(_ v: Video) {
        if let i = d.watchLater.firstIndex(where: { $0.id == v.id }) { d.watchLater.remove(at: i) } else { d.watchLater.insert(v, at: 0) }
        save()
    }

    func removeWatchLater(_ id: String) { d.watchLater.removeAll { $0.id == id }; save() }
    func removeLiked(_ id: String) { d.liked.removeAll { $0.id == id }; save() }

    func createPlaylist(_ name: String, with v: Video?) {
        var p = Playlist(name: name)
        if let v { p.videos = [v] }
        d.playlists.insert(p, at: 0)
        save()
    }

    func inPlaylist(_ pid: String, _ vid: String) -> Bool {
        d.playlists.first { $0.id == pid }?.videos.contains { $0.id == vid } ?? false
    }

    func togglePlaylist(_ pid: String, _ v: Video) {
        guard let i = d.playlists.firstIndex(where: { $0.id == pid }) else { return }
        if let j = d.playlists[i].videos.firstIndex(where: { $0.id == v.id }) { d.playlists[i].videos.remove(at: j) } else { d.playlists[i].videos.append(v) }
        save()
    }

    func deletePlaylist(_ pid: String) { d.playlists.removeAll { $0.id == pid }; save() }

    func removeFromPlaylist(_ pid: String, _ vid: String) {
        guard let i = d.playlists.firstIndex(where: { $0.id == pid }) else { return }
        d.playlists[i].videos.removeAll { $0.id == vid }
        save()
    }

    // MARK: Searches
    func addSearch(_ q: String) {
        let q = q.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        d.recentSearches.removeAll { $0.caseInsensitiveCompare(q) == .orderedSame }
        d.recentSearches.insert(q, at: 0)
        if d.recentSearches.count > 20 { d.recentSearches.removeLast() }
        save()
    }

    func removeSearch(_ q: String) { d.recentSearches.removeAll { $0 == q }; save() }
}

// MARK: - Settings

struct SettingsData: Codable {
    var theme: ThemeKind = .pearl
    var eveningMode = true
    var ambient = true
    var hideShortsOnHome = true
    var blockedWords: [String] = []
    var sponsorCategories: [String] = ["sponsor", "selfpromo", "interaction"]
    var autoplay = true
    var dataSaver = false
    var speed: Double = 1
    var rokuIP: String? = nil
    var rokuName: String? = nil

    init() {}

    // Missing keys fall back to defaults, so adding a setting later never wipes the others.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SettingsData()
        theme = (try? c.decode(ThemeKind.self, forKey: .theme)) ?? d.theme
        eveningMode = (try? c.decode(Bool.self, forKey: .eveningMode)) ?? d.eveningMode
        ambient = (try? c.decode(Bool.self, forKey: .ambient)) ?? d.ambient
        hideShortsOnHome = (try? c.decode(Bool.self, forKey: .hideShortsOnHome)) ?? d.hideShortsOnHome
        blockedWords = (try? c.decode([String].self, forKey: .blockedWords)) ?? d.blockedWords
        sponsorCategories = (try? c.decode([String].self, forKey: .sponsorCategories)) ?? d.sponsorCategories
        autoplay = (try? c.decode(Bool.self, forKey: .autoplay)) ?? d.autoplay
        dataSaver = (try? c.decode(Bool.self, forKey: .dataSaver)) ?? d.dataSaver
        speed = (try? c.decode(Double.self, forKey: .speed)) ?? d.speed
        rokuIP = try? c.decode(String.self, forKey: .rokuIP)
        rokuName = try? c.decode(String.self, forKey: .rokuName)
    }
}

@Observable
final class AppSettings {
    static let shared = AppSettings()
    private(set) var d: SettingsData

    init() {
        if let data = UserDefaults.standard.data(forKey: "settings"), let s = try? JSONDecoder().decode(SettingsData.self, from: data) {
            d = s
        } else {
            d = SettingsData()
        }
    }

    func set<T>(_ kp: WritableKeyPath<SettingsData, T>, _ value: T) {
        d[keyPath: kp] = value
        if let data = try? JSONEncoder().encode(d) { UserDefaults.standard.set(data, forKey: "settings") }
    }

    func binding<T>(_ kp: WritableKeyPath<SettingsData, T>) -> Binding<T> {
        Binding(get: { self.d[keyPath: kp] }, set: { self.set(kp, $0) })
    }

    /// Evening mode turns Pearl Glass smoky after 8 pm.
    func currentTheme(at date: Date = Date()) -> Theme {
        let hour = Calendar.current.component(.hour, from: date)
        let evening = d.eveningMode && (hour >= 20 || hour < 6)
        return Theme.make(d.theme, evening: evening)
    }

    func allowed(_ v: Video) -> Bool {
        let words = d.blockedWords.map { $0.lowercased() }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return true }
        let hay = (v.title + " " + v.channel).lowercased()
        return !words.contains { hay.contains($0) }
    }
}
