import SwiftUI

struct YouView: View {
    @Environment(\.theme) private var t
    var lib = Library.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                RowGroup(title: "Google account") { AccountCard() }
                weekCard
                if !lib.d.history.isEmpty {
                    VStack(spacing: 10) {
                        SectionHeader(title: "History", action: "See all") { AppState.shared.push(.list(.history)) }
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                ForEach(lib.d.history.prefix(12)) { v in
                                    Button { PlayerModel.shared.play(v) } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Thumbnail(video: v, radius: 14)
                                            Text(v.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(t.ink).lineLimit(2).multilineTextAlignment(.leading)
                                        }
                                        .frame(width: 150)
                                    }
                                    .buttonStyle(PressStyle())
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                VStack(spacing: 0) {
                    row("clock", "Watch later", "\(lib.d.watchLater.count)") { AppState.shared.push(.list(.watchLater)) }
                    divider
                    row("hand.thumbsup", "Liked videos", "\(lib.d.liked.count)") { AppState.shared.push(.list(.liked)) }
                    divider
                    row("list.bullet", "Your playlists", "\(lib.d.playlists.count)") { AppState.shared.push(.playlists) }
                    divider
                    row("text.line.first.and.arrowtriangle.forward", "Queue", "\(PlayerModel.shared.queue.count)") {
                        if let first = PlayerModel.shared.queue.first {
                            PlayerModel.shared.queue.removeFirst()
                            PlayerModel.shared.play(first)
                        }
                    }
                    divider
                    row("tv", "Cast to TV", Roku.shared.current?.name ?? "Set up") { AppState.shared.showCast = true }
                    divider
                    row("gearshape", "Settings", "") { AppState.shared.push(.settings) }
                }
                .modifier(ListCard())
            }
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(t.dark ? Color.white.opacity(0.12) : .white)
                Image(systemName: "person.fill").font(.system(size: 24)).foregroundStyle(t.ink)
                if let p = GoogleAccount.shared.profile { Avatar(url: p.avatar, name: p.name, size: 58) }
            }
            .frame(width: 58, height: 58)
            .rainbowCircle(width: 2.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(GoogleAccount.shared.profile?.name ?? "You").font(.system(size: 26, weight: .bold)).foregroundStyle(t.ink).lineLimit(1)
                Text("\(lib.d.subscriptions.count) subscriptions · \(lib.d.history.count) watched")
                    .font(.system(size: 13)).foregroundStyle(t.ink2)
            }
            Spacer(minLength: 104)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var weekCard: some View {
        Button { AppState.shared.push(.stats) } label: {
            WeekChart().padding(16).surface(26)
        }
        .buttonStyle(PressStyle())
        .padding(.horizontal, 20)
    }

    private var divider: some View { Rectangle().fill(t.divider).frame(height: 1).padding(.leading, 60) }

    private func row(_ icon: String, _ title: String, _ value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(t.ink)
                    .frame(width: 34, height: 34)
                    .background(t.dark ? Color.white.opacity(0.1) : Color.white.opacity(t.glass ? 0.9 : 1), in: Circle())
                Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(t.ink)
                Spacer()
                Text(value).font(.system(size: 14)).foregroundStyle(t.ink2)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(t.ink3)
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct WeekChart: View {
    @Environment(\.theme) private var t
    var lib = Library.shared

    var body: some View {
        let days = lib.lastSevenDays
        let maxS = max(days.map { $0.seconds }.max() ?? 1, 1)
        let active = days.filter { $0.seconds > 0 }.count
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                CardLabel(text: "Watch time · this week")
                Spacer()
                Text("Daily avg \(formatDuration(lib.weekTotal / Double(max(active, 1))))").font(.system(size: 12)).foregroundStyle(t.ink2)
            }
            Text(formatDuration(lib.weekTotal)).font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(t.ink)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(d.today ? t.accent : t.ink.opacity(0.13))
                            .frame(height: max(8, 64 * d.seconds / maxS))
                        Text(d.label).font(.system(size: 11, weight: .semibold)).foregroundStyle(d.today ? t.ink : t.ink3)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 86, alignment: .bottom)
            .padding(.top, 6)
        }
    }
}

struct StatsView: View {
    @Environment(\.theme) private var t
    @Environment(\.dismiss) private var dismiss
    var lib = Library.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Watch time", subtitle: "Your last 7 days")
                WeekChart().padding(16).surface(26).padding(.horizontal, 20)
                if !lib.topChannels.isEmpty {
                    SectionHeader(title: "Top channels")
                    VStack(spacing: 0) {
                        ForEach(Array(lib.topChannels.enumerated()), id: \.offset) { i, item in
                            HStack {
                                Text("\(i + 1)").font(.system(size: 14, weight: .bold)).foregroundStyle(t.ink3).frame(width: 24)
                                Text(item.0).font(.system(size: 15.5, weight: .medium)).foregroundStyle(t.ink).lineLimit(1)
                                Spacer()
                                Text(formatDuration(item.1)).font(.system(size: 14)).foregroundStyle(t.ink2)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                    }
                    .modifier(ListCard())
                }
            }
            .padding(.bottom, 20)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Back button + big two-line title for pushed screens.
struct PageHeader: View {
    @Environment(\.theme) private var t
    @Environment(\.dismiss) private var dismiss
    var title: String
    var subtitle: String?
    var trailing: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GlassIcon(system: "chevron.left") { dismiss() }
                Spacer()
                if let trailing { trailing }
            }
            if t.usesGreeting {
                Greeting(line1: title, line2: subtitle ?? "")
            } else {
                Text(title).font(.system(size: 24, weight: .bold)).foregroundStyle(t.ink)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }
}

struct VideoListView: View {
    var kind: ListKind
    @Environment(\.theme) private var t
    var lib = Library.shared

    private var videos: [Video] {
        switch kind {
        case .history: return lib.d.history
        case .watchLater: return lib.d.watchLater
        case .liked: return lib.d.liked
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                PageHeader(title: kind.title, subtitle: "\(videos.count) videos", trailing: kind == .history && !videos.isEmpty
                           ? AnyView(Button("Clear") { lib.clearHistory() }.font(.system(size: 14, weight: .semibold)).foregroundStyle(t.ink2))
                           : nil)
                if videos.isEmpty {
                    EmptyState(icon: "tray", title: "Nothing here yet", message: "Videos you add will show up here.")
                }
                if !videos.isEmpty && kind != .history {
                    Button {
                        PlayerModel.shared.queue = Array(videos.dropFirst())
                        PlayerModel.shared.play(videos[0])
                    } label: {
                        Label("Play all", systemImage: "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(t.onAccent)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(t.accent, in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .padding(.horizontal, 20)
                }
                ForEach(videos) { v in
                    VideoRow(video: v) {
                        switch kind {
                        case .history: lib.removeHistory(v.id)
                        case .watchLater: lib.removeWatchLater(v.id)
                        case .liked: lib.removeLiked(v.id)
                        }
                    }
                    .padding(.horizontal, t.glass ? 16 : 12)
                }
            }
            .padding(.bottom, 20)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct PlaylistsView: View {
    @Environment(\.theme) private var t
    @State private var newName = ""
    @State private var askName = false
    var lib = Library.shared

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                PageHeader(title: "Playlists", subtitle: "\(lib.d.playlists.count) saved",
                           trailing: AnyView(GlassIcon(system: "plus") { askName = true }))
                if lib.d.playlists.isEmpty {
                    EmptyState(icon: "list.bullet", title: "No playlists", message: "Tap + or use “Save to playlist…” on any video.")
                }
                ForEach(lib.d.playlists) { pl in
                    Button { AppState.shared.push(.playlist(pl.id)) } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                if let first = pl.videos.first { Thumbnail(video: first, radius: 12) } else {
                                    RoundedRectangle(cornerRadius: 12).fill(t.ink.opacity(0.08)).aspectRatio(16 / 9, contentMode: .fit)
                                }
                            }
                            .frame(width: 120)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pl.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(t.ink)
                                Text("\(pl.videos.count) videos").font(.system(size: 13)).foregroundStyle(t.ink2)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .surface(20)
                    }
                    .buttonStyle(PressStyle())
                    .padding(.horizontal, 16)
                    .contextMenu { Button("Delete", role: .destructive) { lib.deletePlaylist(pl.id) } }
                }
            }
            .padding(.bottom, 20)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .alert("New playlist", isPresented: $askName) {
            TextField("Name", text: $newName)
            Button("Create") { if !newName.isEmpty { lib.createPlaylist(newName, with: nil); newName = "" } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct PlaylistView: View {
    var playlistID: String
    @Environment(\.theme) private var t
    var lib = Library.shared

    var body: some View {
        let pl = lib.d.playlists.first { $0.id == playlistID }
        ScrollView {
            LazyVStack(spacing: 10) {
                PageHeader(title: pl?.name ?? "Playlist", subtitle: "\(pl?.videos.count ?? 0) videos")
                if let pl, !pl.videos.isEmpty {
                    Button {
                        PlayerModel.shared.queue = Array(pl.videos.dropFirst())
                        PlayerModel.shared.play(pl.videos[0])
                    } label: {
                        Label("Play all", systemImage: "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(t.onAccent)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(t.accent, in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .padding(.horizontal, 20)
                    ForEach(pl.videos) { v in
                        VideoRow(video: v) { lib.removeFromPlaylist(pl.id, v.id) }
                            .padding(.horizontal, t.glass ? 16 : 12)
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct SaveSheet: View {
    var video: Video
    @Environment(\.theme) private var t
    @State private var newName = ""
    var lib = Library.shared

    var body: some View {
        GlassSheet(title: "Save to…", subtitle: video.title) {
            RowGroup(title: nil) {
                check("clock", "Watch later", lib.inWatchLater(video.id)) { lib.toggleWatchLater(video) }
                ForEach(lib.d.playlists) { pl in
                    RowDivider(inset: 58)
                    check("list.bullet", pl.name, lib.inPlaylist(pl.id, video.id)) { lib.togglePlaylist(pl.id, video) }
                }
            }
            RowGroup(title: "New playlist") {
                HStack {
                    TextField("Name", text: $newName).foregroundStyle(t.ink)
                    Button("Create") {
                        guard !newName.isEmpty else { return }
                        lib.createPlaylist(newName, with: video)
                        newName = ""
                    }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(t.ink)
                    .disabled(newName.isEmpty)
                }
                .padding(.horizontal, 16).frame(height: 54)
            }
        }
    }

    private func check(_ icon: String, _ title: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(t.ink)
                    .frame(width: 30, height: 30)
                    .background(t.dark ? Color.white.opacity(0.1) : Color.white.opacity(0.9), in: Circle())
                Text(title).font(.system(size: 15.5, weight: .medium)).foregroundStyle(t.ink)
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundStyle(on ? t.toggleTint : t.ink3)
            }
            .padding(.horizontal, 16).frame(height: 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
    }
}
