import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.theme) private var t
    var settings = AppSettings.shared
    var lib = Library.shared
    var account = GoogleAccount.shared
    @State private var newWord = ""
    @State private var importing = false
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Settings", subtitle: "Make it yours")

                RowGroup(title: "Google account") {
                    AccountCard()
                }

                RowGroup(title: "Look") {
                    NavRow(icon: "paintpalette", title: "Theme", value: settings.d.theme.title) { AppState.shared.push(.appearance) }
                    RowDivider(inset: 58)
                    ToggleRow(icon: "rays", title: "Ambient mode", note: "The video's colours glow softly around the player", isOn: settings.binding(\.ambient))
                    if settings.d.ambient {
                        SliderRow(title: "Strength", valueLabel: "\(Int(settings.d.ambientStrength * 100))%", value: settings.binding(\.ambientStrength))
                    }
                }

                RowGroup(title: "Feed") {
                    ToggleRow(icon: "play.rectangle.on.rectangle", title: "Hide Shorts", note: "Keeps Shorts off Home (they stay in the Shorts tab)", isOn: settings.binding(\.hideShortsOnHome))
                    RowDivider(inset: 58)
                    ChoiceRow(icon: "timer", title: "Maximum video length",
                              options: [("None", 0), ("10 min", 10), ("20 min", 20), ("30 min", 30), ("60 min", 60)],
                              selection: settings.d.maxLengthMinutes) { settings.set(\.maxLengthMinutes, $0) }
                    RowDivider(inset: 58)
                    mutedWords
                    if !settings.d.blockedChannels.isEmpty {
                        RowDivider(inset: 58)
                        blockedChannels
                    }
                }

                RowGroup(title: "Playback") {
                    ToggleRow(icon: "forward.end", title: "Autoplay next video", isOn: settings.binding(\.autoplay))
                    RowDivider(inset: 58)
                    ToggleRow(icon: "arrow.up.left.and.arrow.down.right", title: "Fill screen in fullscreen", note: "Uses the whole display, around the camera too", isOn: settings.binding(\.fillScreen))
                    RowDivider(inset: 58)
                    ToggleRow(icon: "dollarsign.circle", title: "Skip sponsors", note: "Auto-skips sponsor segments with SponsorBlock", isOn: settings.skipGroup(["sponsor"]))
                    RowDivider(inset: 58)
                    ToggleRow(icon: "megaphone", title: "Skip self-promo & reminders", isOn: settings.skipGroup(["selfpromo", "interaction"]))
                    RowDivider(inset: 58)
                    ToggleRow(icon: "film.stack", title: "Skip intros & outros", isOn: settings.skipGroup(["intro", "outro"]))
                    RowDivider(inset: 58)
                    ToggleRow(icon: "music.note", title: "Skip non-music parts", note: "In music videos", isOn: settings.skipGroup(["music_offtopic"]))
                }

                RowGroup(title: "Data") {
                    ToggleRow(icon: "antenna.radiowaves.left.and.right", title: "Data saver", note: "Start videos at 480p", isOn: settings.binding(\.dataSaver))
                }

                RowGroup(title: "TV") {
                    NavRow(icon: "tv", title: "Roku TV", value: Roku.shared.current?.name ?? "Not set up") { AppState.shared.showCast = true }
                }

                RowGroup(title: "History & privacy") {
                    NavRow(icon: "clock.arrow.circlepath", title: "Manage all history", value: "\(lib.d.history.count)") { AppState.shared.push(.list(.history)) }
                    RowDivider(inset: 58)
                    NavRow(icon: "chart.bar", title: "Watch time", note: "This week and your top channels") { AppState.shared.push(.stats) }
                    RowDivider(inset: 58)
                    NavRow(icon: "trash", title: "Clear watch history", tint: t.danger, chevron: false) { confirmClear = true }
                }

                RowGroup(title: "Your data") {
                    ShareLink(item: BackupFile(data: lib.exportData()), preview: SharePreview("Premium backup")) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .semibold)).foregroundStyle(t.ink)
                                .frame(width: 30, height: 30)
                                .background(t.dark ? Color.white.opacity(0.1) : Color.white.opacity(0.9), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Back up library").font(.system(size: 15.5, weight: .medium)).foregroundStyle(t.ink)
                                Text("Save history, playlists, subscriptions and rules to a file").font(.system(size: 12)).foregroundStyle(t.ink2)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)
                    }
                    .buttonStyle(.plain)
                    RowDivider(inset: 58)
                    NavRow(icon: "square.and.arrow.down", title: "Restore from backup", note: "Replaces your library with the file's") { importing = true }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Premium for iPhone \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · open source · no ads")
                    Text("Everything stays on this phone.")
                }
                .font(.system(size: 12.5))
                .foregroundStyle(t.ink3)
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), lib.importData(data) {
                PlayerModel.shared.showToast("Restored your library")
            } else {
                PlayerModel.shared.showToast("That isn't a Premium backup file")
            }
        }
        .confirmationDialog("Clear watch history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { lib.clearHistory() }
        }
    }

    private var mutedWords: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Muted keywords").font(.system(size: 15.5, weight: .medium)).foregroundStyle(t.ink)
                Text("Videos with these words in the title are hidden.").font(.system(size: 12)).foregroundStyle(t.ink2)
            }
            HStack {
                TextField("Add a word", text: $newWord).foregroundStyle(t.ink).onSubmit(addWord)
                Button("Add", action: addWord).font(.system(size: 14, weight: .semibold)).foregroundStyle(t.ink).disabled(newWord.isEmpty)
            }
            .padding(.horizontal, 14).frame(height: 42)
            .background(t.ink.opacity(0.06), in: Capsule())
            if !settings.d.blockedWords.isEmpty {
                FlowChips(words: settings.d.blockedWords) { w in
                    settings.set(\.blockedWords, settings.d.blockedWords.filter { $0 != w })
                }
            }
        }
        .padding(16)
    }

    private var blockedChannels: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Blocked channels").font(.system(size: 15.5, weight: .medium)).foregroundStyle(t.ink)
            ForEach(settings.d.blockedChannels) { c in
                HStack(spacing: 10) {
                    Avatar(url: c.avatar, name: c.name, size: 28)
                    Text(c.name).font(.system(size: 14.5)).foregroundStyle(t.ink).lineLimit(1)
                    Spacer()
                    Button("Unblock") { settings.unblockChannel(c.id) }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(t.ink2)
                }
            }
        }
        .padding(16)
    }

    private func addWord() {
        let w = newWord.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty, !settings.d.blockedWords.contains(w) else { return }
        settings.set(\.blockedWords, settings.d.blockedWords + [w])
        newWord = ""
    }
}

/// Google account card: sign in, import from YouTube, sign out — like the Android Library screen.
struct AccountCard: View {
    @Environment(\.theme) private var t
    var account = GoogleAccount.shared
    var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let p = account.profile {
                HStack(spacing: 12) {
                    Avatar(url: p.avatar, name: p.name, size: 44).rainbowCircle(width: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(t.ink)
                        Text(p.handle ?? "Signed in with Google").font(.system(size: 12.5)).foregroundStyle(t.ink2)
                    }
                    Spacer()
                    Menu {
                        Button(role: .destructive) { account.signOut() } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(t.ink2).frame(width: 34, height: 34)
                    }
                }
                .padding(16)
                RowDivider()
                NavRow(icon: "arrow.down.circle", title: account.busy ? "Importing…" : "Import from YouTube",
                       note: "Subscriptions, playlists and liked videos", chevron: false) {
                    Task { await account.importAll() }
                }
                .disabled(account.busy)
                RowDivider(inset: 58)
                ToggleRow(icon: "arrow.triangle.2.circlepath", title: "Stay in sync", note: "Picks up new subscriptions once a day", isOn: settings.binding(\.syncOnLaunch))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Bring your YouTube with you").font(.system(size: 16, weight: .semibold)).foregroundStyle(t.ink)
                    Text("Sign in to import your subscriptions, playlists and liked videos. You stay signed in on this iPhone until you sign out. Premium only reads your account — it never posts or changes anything.")
                        .font(.system(size: 13)).foregroundStyle(t.ink2)
                    Button { Task { await account.signIn() } } label: {
                        HStack(spacing: 8) {
                            if account.busy { ProgressView().tint(t.onAccent) } else { Image(systemName: "person.crop.circle.badge.checkmark") }
                            Text("Sign in with Google")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(t.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(t.accent, in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(account.busy)
                }
                .padding(16)
            }
            if let s = account.status {
                Text(s).font(.system(size: 12.5)).foregroundStyle(t.ink2).padding(.horizontal, 16).padding(.bottom, 14)
            }
        }
    }
}

struct BackupFile: Transferable {
    var data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName("Premium-backup.json")
    }
}

/// Removable word chips that wrap onto new lines.
struct FlowChips: View {
    @Environment(\.theme) private var t
    var words: [String]
    var onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(words, id: \.self) { w in
                Button { onRemove(w) } label: {
                    HStack(spacing: 6) {
                        Text(w)
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(t.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .surface(16, strong: true)
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

struct AppearanceView: View {
    @Environment(\.theme) private var t
    var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Appearance", subtitle: "Pick your look")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(ThemeKind.allCases) { kind in
                        ThemePreview(kind: kind, selected: settings.d.theme == kind) {
                            withAnimation(Motion.spring) { settings.set(\.theme, kind) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                RowGroup(title: nil) {
                    ToggleRow(icon: "moon.stars", title: "Evening mode", note: "Pearl Glass turns smoky after 8 pm", isOn: settings.binding(\.eveningMode))
                    RowDivider(inset: 58)
                    ToggleRow(icon: "rays", title: "Ambient mode", note: "The video's colours glow softly around the player", isOn: settings.binding(\.ambient))
                    if settings.d.ambient {
                        SliderRow(title: "Strength", valueLabel: "\(Int(settings.d.ambientStrength * 100))%", value: settings.binding(\.ambientStrength))
                    }
                }
                Text("Reduce Motion and Reduce Transparency in iPhone Settings → Accessibility are respected too.")
                    .font(.system(size: 12.5)).foregroundStyle(t.ink3).padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

}

/// Mini picture of a theme for the picker.
struct ThemePreview: View {
    @Environment(\.theme) private var t
    var kind: ThemeKind
    var selected: Bool
    var action: () -> Void

    var body: some View {
        let p = Theme.make(kind, evening: false)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [p.blobs[0].opacity(p.blobOpacity > 0 ? 1 : 0), p.bgTop, p.blobs[3].opacity(p.blobOpacity > 0 ? 1 : 0)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .background(p.bgTop)
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(p.ink.opacity(0.85)).frame(width: 64, height: 7)
                        Capsule().fill(p.ink.opacity(0.3)).frame(width: 46, height: 7)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: p.glass ? 8 : 3).fill(p.glass ? p.glassFillStrong : p.card).frame(height: 26)
                            }
                        }
                        .padding(.top, 4)
                        RoundedRectangle(cornerRadius: p.glass ? 8 : 3).fill(p.glass ? p.glassFillStrong : p.card).frame(height: 24)
                        Spacer(minLength: 0)
                        Capsule().fill(p.glass ? p.glassFillStrong : p.card).frame(height: 14)
                            .overlay(Capsule().fill(p.accent).frame(width: 22, height: 8), alignment: .leading)
                    }
                    .padding(10)
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(kind.title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(t.ink)
                        Text(kind.subtitle).font(.system(size: 11.5)).foregroundStyle(t.ink2)
                    }
                    Spacer()
                    ZStack {
                        if selected {
                            Circle().fill(t.accent)
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(t.onAccent)
                        } else {
                            Circle().strokeBorder(t.ink3, lineWidth: 1.5)
                        }
                    }
                    .frame(width: 22, height: 22)
                }
                .padding(.horizontal, 4)
            }
            .padding(8)
            .surface(22, strong: selected)
            .rainbowEdge(22, on: selected)
        }
        .buttonStyle(PressStyle())
    }
}
