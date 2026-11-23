import SwiftUI
import AVKit

/// The watch page: video at the top, a glass sheet with everything else below.
struct WatchView: View {
    @Environment(\.theme) private var t
    @Environment(\.verticalSizeClass) private var vSize
    var p = PlayerModel.shared
    var lib = Library.shared
    @State private var drag: CGFloat = 0
    @State private var showDescription = false
    @State private var showComments = false
    @State private var showSettings = false
    @State private var fullscreen = false

    var body: some View {
        let landscape = vSize == .compact
        Group {
            if landscape || fullscreen {
                PlayerArea(fullscreen: true, onCollapse: collapse, onSettings: { showSettings = true }, onFullscreen: { fullscreen.toggle() })
                    .ignoresSafeArea()
                    .background(Color.black.ignoresSafeArea())
            } else {
                portrait
            }
        }
        .offset(y: max(0, drag))
        .sheet(isPresented: $showComments) {
            CommentsSheet().presentationDetents([.medium, .large]).environment(\.theme, t)
        }
        .sheet(isPresented: $showSettings) {
            PlayerSettingsSheet().presentationDetents([.medium, .large]).environment(\.theme, t)
        }
    }

    private func collapse() {
        withAnimation(Motion.spring) { p.expanded = false }
    }

    private var portrait: some View {
        ZStack(alignment: .top) {
            Backdrop().ignoresSafeArea()
            if AppSettings.shared.d.ambient, let v = p.current, t.glass {
                Thumbnail(video: v, radius: 0)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(1.6)
                    .blur(radius: 50)
                    .opacity(t.dark ? 0.55 : 0.6)
                    .frame(height: 380)
                    .clipped()
                    .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
                    .ignoresSafeArea()
            }
            VStack(spacing: 0) {
                PlayerArea(fullscreen: false, onCollapse: collapse, onSettings: { showSettings = true }, onFullscreen: { fullscreen = true })
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onChanged { g in if g.translation.height > 0 { drag = g.translation.height } }
                            .onEnded { g in
                                if g.translation.height > 120 || g.predictedEndTranslation.height > 260 { collapse() }
                                withAnimation(Motion.spring) { drag = 0 }
                            }
                    )
                ScrollView {
                    if let v = p.current { content(v) }
                }
                .scrollIndicators(.hidden)
                .modifier(SheetSurface())
                .padding(.top, t.glass ? 10 : 0)
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ v: Video) -> some View {
        let d = p.details
        VStack(alignment: .leading, spacing: 16) {
            if t.glass {
                Capsule().fill(t.ink3.opacity(0.6)).frame(width: 40, height: 5).frame(maxWidth: .infinity).padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(v.title.isEmpty ? (d?.video.title ?? "") : v.title)
                    .font(.system(size: 21, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(t.ink)
                Button { withAnimation(Motion.spring) { showDescription.toggle() } } label: {
                    (Text([d?.views ?? v.views, d?.date ?? v.published].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") + "  ")
                        .foregroundColor(t.ink2)
                     + Text(showDescription ? "less" : "…more").bold().foregroundColor(t.ink))
                        .font(.system(size: 13.5))
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }
            if showDescription, let desc = d?.description, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 14))
                    .foregroundStyle(t.ink)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surface(20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            channelRow(v, d)
            actions(v, d)
            if let chapters = d?.chapters, !chapters.isEmpty { chapterRow(chapters) }
            commentsCard(d)
            if !p.queue.isEmpty { queueSection }
            if let related = d?.related, !related.isEmpty {
                CardLabel(text: "Up next")
                ForEach(related.filter { AppSettings.shared.allowed($0) }) { r in
                    VideoRow(video: r, thumbWidth: 160)
                }
            } else if d == nil {
                LoadingDots()
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 60)
    }

    private func channelRow(_ v: Video, _ d: VideoDetails?) -> some View {
        let channel = d?.channel ?? v.channelId.map { Channel(id: $0, name: v.channel, avatar: v.channelAvatar) }
        let subscribed = lib.isSubscribed(channel?.id)
        return HStack(spacing: 12) {
            Button {
                if let c = channel { collapse(); AppState.shared.push(.channel(id: c.id, name: c.name)) }
            } label: {
                HStack(spacing: 10) {
                    Avatar(url: channel?.avatar ?? v.channelAvatar, name: channel?.name ?? v.channel, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(channel?.name ?? v.channel).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(t.ink).lineLimit(1)
                        if let s = channel?.subscribers { Text(s).font(.system(size: 12.5)).foregroundStyle(t.ink2) }
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if let c = channel {
                Button { withAnimation(Motion.spring) { lib.toggleSubscribe(c) } } label: {
                    Text(subscribed ? "Subscribed" : "Subscribe")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(subscribed ? t.ink : t.onSubscribe)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background { if !subscribed { Capsule().fill(t.subscribe) } }
                        .modifier(SubscribedSurface(on: subscribed))
                }
                .buttonStyle(PressStyle())
                .sensoryFeedback(.success, trigger: subscribed)
            }
        }
    }

    private func actions(_ v: Video, _ d: VideoDetails?) -> some View {
        let liked = lib.isLiked(v.id)
        let disliked = lib.isDisliked(v.id)
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button { lib.toggleLike(v) } label: {
                        Label(d?.likes ?? "Like", systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                    }
                    Rectangle().fill(t.divider).frame(width: 1, height: 18)
                    Button { lib.toggleDislike(v) } label: {
                        Image(systemName: disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    }
                }
                .modifier(ActionPill())
                ShareLink(item: v.shareURL) { Label("Share", systemImage: "arrowshape.turn.up.right") }.modifier(ActionPill())
                Button { AppState.shared.saveTarget = v } label: {
                    Label(lib.inWatchLater(v.id) ? "Saved" : "Save", systemImage: lib.inWatchLater(v.id) ? "bookmark.fill" : "bookmark")
                }
                .modifier(ActionPill())
                Button { AppState.shared.showCast = true } label: { Label("Cast", systemImage: "tv") }.modifier(ActionPill())
                Button { p.setAudioOnly(!p.audioOnly) } label: {
                    Label(p.audioOnly ? "Video" : "Audio only", systemImage: p.audioOnly ? "play.rectangle" : "headphones")
                }
                .modifier(ActionPill())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -18)
        .contentMargins(.horizontal, 18, for: .scrollContent)
    }

    private func chapterRow(_ chapters: [Chapter]) -> some View {
        let currentIndex = chapters.lastIndex { $0.start <= p.time } ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "Chapters")
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(chapters.enumerated()), id: \.element.id) { i, c in
                            Button { p.seek(c.start) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    if let th = c.thumbnail, let u = URL(string: th) {
                                        Color.clear.aspectRatio(16 / 9, contentMode: .fit)
                                            .overlay { RemoteImage(urls: [u]) }
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    Text(c.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(t.ink).lineLimit(1)
                                    Text(formatTime(c.start)).font(.system(size: 11)).foregroundStyle(t.ink2)
                                }
                                .padding(7)
                                .frame(width: 140)
                                .surface(18)
                                .rainbowEdge(18, on: i == currentIndex)
                            }
                            .buttonStyle(PressStyle())
                            .id(i)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .onChange(of: currentIndex) { _, i in withAnimation(Motion.spring) { proxy.scrollTo(i, anchor: .center) } }
            }
        }
    }

    private func commentsCard(_ d: VideoDetails?) -> some View {
        Button { showComments = true } label: {
            HStack {
                Text("Comments").font(.system(size: 15, weight: .semibold)).foregroundStyle(t.ink)
                if let c = d?.commentCount { Text(c).font(.system(size: 15)).foregroundStyle(t.ink2) }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(t.ink2)
            }
            .padding(14)
            .surface(20)
        }
        .buttonStyle(PressStyle())
        .disabled(d?.commentsToken == nil)
        .opacity(d?.commentsToken == nil && d != nil ? 0.5 : 1)
    }

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardLabel(text: "Your queue · \(p.queue.count)")
                Spacer()
                Button("Clear") { p.queue = [] }.font(.system(size: 13, weight: .semibold)).foregroundStyle(t.ink2)
            }
            ForEach(p.queue) { q in
                VideoRow(video: q, thumbWidth: 120) { p.queue.removeAll { $0.id == q.id } }
            }
        }
    }
}

private struct SheetSurface: ViewModifier {
    @Environment(\.theme) private var t
    @ViewBuilder func body(content: Content) -> some View {
        if t.glass {
            content
                .background(t.glassFillStrong)
                .background(.ultraThinMaterial)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [t.strokeTop, .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
                )
        } else {
            content.background(Color.white)
        }
    }
}

private struct ActionPill: ViewModifier {
    @Environment(\.theme) private var t
    func body(content: Content) -> some View {
        content
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(t.ink)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .surface(19)
    }
}

private struct SubscribedSurface: ViewModifier {
    var on: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if on { content.surface(20) } else { content }
    }
}

// MARK: - Player area

struct PlayerArea: View {
    @Environment(\.theme) private var t
    var fullscreen: Bool
    var onCollapse: () -> Void
    var onSettings: () -> Void
    var onFullscreen: () -> Void
    var p = PlayerModel.shared
    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing: Double?
    @State private var flash: String?

    var body: some View {
        ZStack {
            Color.black
            if p.audioOnly, let v = p.current {
                Thumbnail(video: v, radius: 0, large: true).blur(radius: 2).overlay(Color.black.opacity(0.35))
                Image(systemName: "headphones").font(.system(size: 40, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
            } else {
                VideoSurface(main: true)
            }
            gestureLayer
            if let flash {
                Image(systemName: flash).font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                    .padding(18).background(.black.opacity(0.35), in: Circle())
                    .transition(.scale.combined(with: .opacity))
            }
            if showControls || p.loading || !p.isPlaying { controls.transition(.opacity) }
            if let e = p.error {
                VStack(spacing: 10) {
                    Text(e).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                    Button("Try again") { p.error = nil; p.reload() }
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 16).padding(.vertical, 8).background(.white, in: Capsule())
                }
                .padding(20)
            }
        }
        .aspectRatio(fullscreen ? nil : 16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: fullscreen ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: fullscreen || !t.glass ? 0 : 22, style: .continuous))
        .padding(.horizontal, fullscreen || !t.glass ? 0 : 10)
        .onAppear { scheduleHide() }
        .statusBarHidden(fullscreen)
        .persistentSystemOverlays(fullscreen ? .hidden : .automatic)
    }

    private var gestureLayer: some View {
        HStack(spacing: 0) {
            Color.clear.contentShape(Rectangle())
                .onTapGesture(count: 2) { doubleTap(-10) }
                .onTapGesture { toggleControls() }
            Color.clear.contentShape(Rectangle())
                .onTapGesture(count: 2) { doubleTap(10) }
                .onTapGesture { toggleControls() }
        }
    }

    private func doubleTap(_ delta: Double) {
        p.skip(delta)
        withAnimation(.easeOut(duration: 0.15)) { flash = delta > 0 ? "goforward.10" : "gobackward.10" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { withAnimation { flash = nil } }
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
        if showControls { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled, scrubbing == nil, p.isPlaying else { return }
            withAnimation(.easeInOut(duration: 0.3)) { showControls = false }
        }
    }

    private var currentChapter: String? {
        guard let chapters = p.details?.chapters, !chapters.isEmpty else { return nil }
        let at = scrubbing ?? p.time
        return chapters.last { $0.start <= at }?.title
    }

    private var controls: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.45), .clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack {
                HStack(spacing: 10) {
                    roundButton(fullscreen ? "arrow.down.right.and.arrow.up.left" : "chevron.down") {
                        if fullscreen { onFullscreen() } else { onCollapse() }
                    }
                    Spacer()
                    roundButton("tv") { AppState.shared.showCast = true }
                    if p.pipPossible { roundButton("pip.enter") { p.startPiP() } }
                    roundButton("gearshape") { onSettings() }
                }
                Spacer()
                HStack(spacing: 38) {
                    Button { p.skip(-10); scheduleHide() } label: { Image(systemName: "gobackward.10").font(.system(size: 24, weight: .semibold)) }
                    Button { p.toggle(); scheduleHide() } label: {
                        ZStack {
                            if p.loading {
                                ProgressView().tint(.white).scaleEffect(1.2)
                            } else {
                                Image(systemName: p.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 28, weight: .bold))
                            }
                        }
                        .frame(width: 64, height: 64)
                        .background(.ultraThinMaterial.opacity(0.8), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    }
                    Button { p.skip(10); scheduleHide() } label: { Image(systemName: "goforward.10").font(.system(size: 24, weight: .semibold)) }
                }
                .foregroundStyle(.white)
                .buttonStyle(PressStyle())
                Spacer()
                VStack(spacing: 6) {
                    HStack {
                        Text(formatTime(scrubbing ?? p.time) + (currentChapter.map { " · \($0)" } ?? ""))
                            .lineLimit(1)
                        Spacer()
                        Text(formatTime(p.duration))
                        Button(action: onFullscreen) {
                            Image(systemName: fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 14, weight: .bold))
                                .padding(.leading, 8)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    SeekBar(time: p.time, duration: p.duration, chapters: p.details?.chapters ?? [], segments: p.segments, scrubbing: $scrubbing) { s in
                        p.seek(s)
                        scheduleHide()
                    }
                }
            }
            .padding(12)
            .padding(.horizontal, fullscreen ? 30 : 0)
        }
    }

    private func roundButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: { action(); scheduleHide() }) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial.opacity(0.7), in: Circle())
        }
        .buttonStyle(PressStyle())
    }
}

/// Seek bar with chapter gaps and SponsorBlock segments. Drag to scrub.
struct SeekBar: View {
    var time: Double
    var duration: Double
    var chapters: [Chapter]
    var segments: [SkipSegment]
    @Binding var scrubbing: Double?
    var onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let shown = scrubbing ?? time
            let frac = duration > 0 ? max(0, min(1, shown / duration)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3)).frame(height: scrubbing == nil ? 4 : 7)
                ForEach(segments, id: \.self) { s in
                    if duration > 0 {
                        Rectangle().fill(Color(hex: 0x34C79A).opacity(0.9))
                            .frame(width: max(2, w * (s.end - s.start) / duration), height: scrubbing == nil ? 4 : 7)
                            .offset(x: w * s.start / duration)
                    }
                }
                Capsule().fill(.white).frame(width: w * frac, height: scrubbing == nil ? 4 : 7)
                ForEach(chapters.dropFirst()) { c in
                    if duration > 0 {
                        Rectangle().fill(.black.opacity(0.6)).frame(width: 2, height: 8).offset(x: w * c.start / duration - 1)
                    }
                }
                Circle().fill(.white)
                    .frame(width: scrubbing == nil ? 13 : 18, height: scrubbing == nil ? 13 : 18)
                    .shadow(color: .black.opacity(0.3), radius: 3)
                    .offset(x: w * frac - (scrubbing == nil ? 6.5 : 9))
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard duration > 0 else { return }
                        scrubbing = max(0, min(duration, Double(v.location.x / w) * duration))
                    }
                    .onEnded { _ in
                        if let s = scrubbing { onSeek(s) }
                        scrubbing = nil
                    }
            )
            .animation(.easeOut(duration: 0.15), value: scrubbing == nil)
        }
        .frame(height: 24)
    }
}

// MARK: - Sheets

struct CommentsSheet: View {
    @Environment(\.theme) private var t
    var p = PlayerModel.shared
    @State private var items: [Comment] = []
    @State private var next: String?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Comments").font(.system(size: 20, weight: .bold)).foregroundStyle(t.ink)
                if let c = p.details?.commentCount { Text(c).font(.system(size: 17)).foregroundStyle(t.ink2) }
            }
            .padding(20)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(items) { c in
                        HStack(alignment: .top, spacing: 12) {
                            Avatar(url: c.avatar, name: c.author, size: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(c.author) · \(c.published)").font(.system(size: 12)).foregroundStyle(t.ink2)
                                Text(c.text).font(.system(size: 14.5)).foregroundStyle(t.ink).textSelection(.enabled)
                                HStack(spacing: 14) {
                                    Label(c.likes.isEmpty ? "0" : c.likes, systemImage: "hand.thumbsup")
                                    if !c.replies.isEmpty && c.replies != "0" { Label(c.replies, systemImage: "bubble.left") }
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(t.ink2)
                            }
                        }
                        .onAppear { if c.id == items.last?.id { Task { await load() } } }
                    }
                    if loading { LoadingDots() }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .presentationBackground(.ultraThinMaterial)
        .task {
            next = p.details?.commentsToken
            await load()
        }
    }

    @MainActor
    private func load() async {
        guard let token = next, !loading else { return }
        loading = true
        if let r = try? await InnerTube.shared.comments(token) {
            let ids = Set(items.map(\.id))
            items += r.items.filter { !ids.contains($0.id) }
            next = r.next
        } else {
            next = nil
        }
        loading = false
    }
}

struct PlayerSettingsSheet: View {
    @Environment(\.theme) private var t
    var p = PlayerModel.shared
    var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Playback speed") {
                    Picker("Speed", selection: Binding(get: { p.speed }, set: { p.setSpeed($0) })) {
                        ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 1.75, 2], id: \.self) { s in
                            Text(s == 1 ? "Normal" : String(format: "%gx", s)).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Quality") {
                    Toggle("Audio only", isOn: Binding(get: { p.audioOnly }, set: { p.setAudioOnly($0) }))
                    Toggle("Data saver (480p max)", isOn: Binding(get: { settings.d.dataSaver }, set: { settings.set(\.dataSaver, $0); p.reload() }))
                }
                Section("Sleep timer") {
                    ForEach([15, 30, 45, 60], id: \.self) { m in
                        Button("\(m) minutes") { p.setSleep(minutes: m) }
                    }
                    Button("End of video") { p.setSleepAtEnd() }
                    if p.sleepAt != nil || p.sleepAtEnd {
                        Button("Turn off", role: .destructive) { p.setSleep(minutes: nil) }
                    }
                }
                Section {
                    Toggle("Autoplay next video", isOn: settings.binding(\.autoplay))
                } footer: {
                    Text("SponsorBlock skips are set in Settings.")
                }
            }
            .navigationTitle("Player")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
