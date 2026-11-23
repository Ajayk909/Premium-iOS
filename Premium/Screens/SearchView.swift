import SwiftUI

struct SearchView: View {
    var initial: String?
    @Environment(\.theme) private var t
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var submitted = ""
    @State private var filter: InnerTube.Filter = .none
    @State private var results: [Video] = []
    @State private var continuation: String?
    @State private var suggestions: [String] = []
    @State private var loading = false
    @State private var voice = VoiceSearch()
    @FocusState private var focused: Bool
    var lib = Library.shared

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if !submitted.isEmpty && !focused { filters }
            ScrollView {
                LazyVStack(spacing: 12) {
                    if focused || submitted.isEmpty {
                        suggestionList
                    } else if loading && results.isEmpty {
                        LoadingDots()
                    } else if results.isEmpty {
                        EmptyState(icon: "magnifyingglass", title: "No results", message: "Try different words or another filter.")
                    } else {
                        resultList
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .overlay(alignment: .bottom) { if voice.listening { voiceBubble } }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if initial == "__voice__" {
                startVoice()
            } else if let initial, !initial.isEmpty, submitted.isEmpty {
                query = initial
                submit()
            } else if submitted.isEmpty {
                focused = true
            }
        }
        .onDisappear { voice.stop() }
        .task(id: query) {
            guard focused else { return }
            try? await Task.sleep(nanoseconds: 180_000_000)
            suggestions = await InnerTube.shared.suggestions(query)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            GlassIcon(system: "chevron.left") { dismiss() }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(t.ink2)
                TextField("Search Premium", text: $query)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit(submit)
                    .foregroundStyle(t.ink)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = ""; focused = true } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(t.ink3)
                    }
                }
            }
            .font(.system(size: 16))
            .padding(.horizontal, 14)
            .frame(height: 46)
            .surface(23, strong: true, chrome: true)
            Button(action: startVoice) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(t.ink)
                    .frame(width: 44, height: 44)
                    .surface(22, strong: true)
                    .rainbowCircle(on: voice.listening, width: 2.5)
            }
            .buttonStyle(PressStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(InnerTube.Filter.allCases) { f in
                    Chip(title: f.title, selected: filter == f) {
                        filter = f
                        Task { await run() }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var suggestionList: some View {
        let list: [SuggestionItem] = query.isEmpty
            ? lib.d.recentSearches.map { SuggestionItem(text: $0, recent: true) }
            : suggestions.map { s in SuggestionItem(text: s, recent: lib.d.recentSearches.contains(s)) }
        if list.isEmpty && query.isEmpty {
            EmptyState(icon: "sparkle.magnifyingglass", title: "Search YouTube, without ads", message: "Type or tap the mic.")
        }
        VStack(spacing: 0) {
            ForEach(list, id: \.text) { item in
                HStack(spacing: 14) {
                    Image(systemName: item.recent ? "clock.arrow.circlepath" : "magnifyingglass").foregroundStyle(t.ink2).frame(width: 22)
                    Text(item.text).foregroundStyle(t.ink).lineLimit(1)
                    Spacer()
                    if item.recent && query.isEmpty {
                        Button { lib.removeSearch(item.text) } label: { Image(systemName: "xmark").foregroundStyle(t.ink3) }
                            .buttonStyle(.plain)
                    } else {
                        Button { query = item.text + " " } label: { Image(systemName: "arrow.up.left").foregroundStyle(t.ink3) }
                            .buttonStyle(.plain)
                    }
                }
                .font(.system(size: 16))
                .padding(.horizontal, 16)
                .frame(height: 48)
                .contentShape(Rectangle())
                .onTapGesture { query = item.text; submit() }
                if item.text != list.last?.text { Rectangle().fill(t.divider).frame(height: 1).padding(.leading, 52) }
            }
        }
        .modifier(ListCard())
    }

    @ViewBuilder
    private var resultList: some View {
        let shorts = results.filter { $0.isShort }
        let videos = results.filter { !$0.isShort }
        if filter == .shorts {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(shorts) { s in
                    Button { AppState.shared.openShorts(shorts, at: s.id) } label: { ShortTile(video: s, width: (UIScreen.main.bounds.width - 42) / 2) }
                        .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, 16)
        } else {
            ForEach(Array(videos.enumerated()), id: \.element.id) { i, v in
                VideoCard(video: v)
                    .onAppear { if i >= videos.count - 3 { Task { await more() } } }
                if i == 2 && !shorts.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(shorts) { s in
                                Button { AppState.shared.openShorts(shorts, at: s.id) } label: { ShortTile(video: s) }
                                    .buttonStyle(PressStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    private var voiceBubble: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .strokeBorder(AngularGradient(colors: rainbow, center: .center), lineWidth: 3 + voice.level * 6)
                    .frame(width: 78, height: 78)
                    .rotationEffect(.degrees(voice.listening ? 360 : 0))
                    .animation(.linear(duration: 3).repeatForever(autoreverses: false), value: voice.listening)
                Image(systemName: "mic.fill").font(.system(size: 24, weight: .semibold)).foregroundStyle(t.ink)
            }
            Text(voice.transcript.isEmpty ? "Listening…" : voice.transcript)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(voice.transcript.isEmpty ? t.ink2 : t.ink)
                .multilineTextAlignment(.center)
            Button("Cancel") { voice.stop() }.font(.system(size: 14, weight: .semibold)).foregroundStyle(t.ink2)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .surface(28, strong: true)
        .padding(16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func startVoice() {
        focused = false
        PlayerModel.shared.pause()
        voice.start { text in
            query = text
            submit()
        }
    }

    private func submit() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        focused = false
        submitted = q
        lib.addSearch(q)
        Task { await run() }
    }

    @MainActor
    private func run() async {
        loading = true
        results = []
        continuation = nil
        if let page = try? await InnerTube.shared.search(submitted, filter: filter) {
            results = page.items.filter { AppSettings.shared.allowed($0) }
            continuation = page.continuation
        }
        loading = false
    }

    @MainActor
    private func more() async {
        guard let c = continuation, !loading else { return }
        loading = true
        if let page = try? await InnerTube.shared.search(submitted, filter: filter, continuation: c) {
            let ids = Set(results.map(\.id))
            results += page.items.filter { !ids.contains($0.id) && AppSettings.shared.allowed($0) }
            continuation = page.continuation
        } else {
            continuation = nil
        }
        loading = false
    }
}

/// Groups rows into one glass card (glass themes) or leaves them flat (Classic).
struct ListCard: ViewModifier {
    @Environment(\.theme) private var t
    @ViewBuilder func body(content: Content) -> some View {
        if t.glass {
            content.surface(24).padding(.horizontal, 16)
        } else {
            content
        }
    }
}

struct SuggestionItem: Hashable {
    var text: String
    var recent: Bool
}
