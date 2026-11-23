import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.theme) private var t
    var settings = AppSettings.shared
    var lib = Library.shared
    @State private var newWord = ""
    @State private var importing = false
    @State private var confirmClear = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Settings", subtitle: "Make it yours")

                group("Look") {
                    navRow("paintpalette", "Appearance", settings.d.theme.title) { AppState.shared.push(.appearance) }
                }

                group("Playback") {
                    toggleRow("Autoplay next video", settings.binding(\.autoplay))
                    divider
                    toggleRow("Data saver", settings.binding(\.dataSaver), note: "Caps video at 480p")
                    divider
                    toggleRow("Hide Shorts on Home", settings.binding(\.hideShortsOnHome))
                }

                group("SponsorBlock — skip automatically") {
                    ForEach(Array(SponsorBlock.allCategories.enumerated()), id: \.offset) { i, cat in
                        toggleRow(cat.1, Binding(
                            get: { settings.d.sponsorCategories.contains(cat.0) },
                            set: { on in
                                var list = settings.d.sponsorCategories.filter { $0 != cat.0 }
                                if on { list.append(cat.0) }
                                settings.set(\.sponsorCategories, list)
                            }))
                        if i < SponsorBlock.allCategories.count - 1 { divider }
                    }
                }

                group("Blocked words") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Videos whose title or channel contains these words are hidden everywhere.")
                            .font(.system(size: 13)).foregroundStyle(t.ink2)
                        HStack {
                            TextField("Add a word", text: $newWord).foregroundStyle(t.ink).onSubmit(addWord)
                            Button("Add", action: addWord).font(.system(size: 14, weight: .semibold)).disabled(newWord.isEmpty)
                        }
                        .padding(.horizontal, 14).frame(height: 42).surface(21, strong: true)
                        FlowChips(words: settings.d.blockedWords) { w in
                            settings.set(\.blockedWords, settings.d.blockedWords.filter { $0 != w })
                        }
                    }
                    .padding(16)
                }

                group("TV") {
                    navRow("tv", "Roku TV", Roku.shared.current?.name ?? "Not set up") { AppState.shared.showCast = true }
                }

                group("Your data") {
                    ShareLink(item: BackupFile(data: lib.exportData()), preview: SharePreview("Premium backup")) {
                        rowLabel("square.and.arrow.up", "Back up library", nil)
                    }
                    .buttonStyle(.plain)
                    divider
                    navRow("square.and.arrow.down", "Restore from backup", nil) { importing = true }
                    divider
                    navRow("trash", "Clear watch history", nil, tint: t.danger) { confirmClear = true }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Premium for iPhone \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    Text("Personal, open-source and ad-free. Everything stays on this phone.")
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
                PlayerModel.shared.showToast("Library restored")
            } else {
                PlayerModel.shared.showToast("That file isn't a Premium backup")
            }
        }
        .confirmationDialog("Clear all watch history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { lib.clearHistory() }
        }
    }

    private func addWord() {
        let w = newWord.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty, !settings.d.blockedWords.contains(w) else { return }
        settings.set(\.blockedWords, settings.d.blockedWords + [w])
        newWord = ""
    }

    private var divider: some View { Rectangle().fill(t.divider).frame(height: 1).padding(.leading, 16) }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: title).padding(.horizontal, 24)
            VStack(spacing: 0) { content() }.modifier(ListCard())
        }
    }

    private func toggleRow(_ title: String, _ binding: Binding<Bool>, note: String? = nil) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15.5, weight: .medium)).foregroundStyle(t.ink)
                if let note { Text(note).font(.system(size: 12)).foregroundStyle(t.ink2) }
            }
        }
        .tint(t.accent)
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
    }

    private func rowLabel(_ icon: String, _ title: String, _ value: String?, tint: Color? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint ?? t.ink).frame(width: 24)
            Text(title).font(.system(size: 15.5, weight: .medium)).foregroundStyle(tint ?? t.ink)
            Spacer()
            if let value { Text(value).font(.system(size: 14)).foregroundStyle(t.ink2) }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(t.ink3)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .contentShape(Rectangle())
    }

    private func navRow(_ icon: String, _ title: String, _ value: String?, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(icon, title, value, tint: tint) }.buttonStyle(.plain)
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
                VStack(spacing: 0) {
                    toggle("Evening mode", "Pearl Glass turns smoky after 8 pm", settings.binding(\.eveningMode))
                    Rectangle().fill(t.divider).frame(height: 1).padding(.leading, 16)
                    toggle("Ambient glow", "Tints the watch page from the video", settings.binding(\.ambient))
                }
                .modifier(ListCard())
                Text("Reduce Motion and Reduce Transparency in iPhone Settings → Accessibility are respected too.")
                    .font(.system(size: 12.5)).foregroundStyle(t.ink3).padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func toggle(_ title: String, _ note: String, _ b: Binding<Bool>) -> some View {
        Toggle(isOn: b) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15.5, weight: .medium)).foregroundStyle(t.ink)
                Text(note).font(.system(size: 12)).foregroundStyle(t.ink2)
            }
        }
        .tint(t.accent)
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
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
