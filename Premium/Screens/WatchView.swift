import SwiftUI
import AVKit

/// The watch page: video edge to edge at the top, details below. Settings and comments open
/// in a panel under the video, so the video always stays visible.
struct WatchView: View {
    enum Panel { case settings, comments }

    @Environment(\.theme) private var t
    @Environment(\.verticalSizeClass) private var vSize
    var p = PlayerModel.shared
    var lib = Library.shared
    @State private var drag: CGFloat = 0
    @State private var showDescription = false
    @State private var panel: Panel?
    @State private var fullscreen = false

    var body: some View {
        let landscape = vSize == .compact
        Group {
            if landscape || fullscreen {
                fullscreenView
            } else {
                portrait
            }
        }
        .offset(y: max(0, drag))
        .scaleEffect(1 - min(0.12, max(0, drag) / 2400), anchor: .top)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.86), value: drag)
    }

    private func collapse() {
        withAnimation(Motion.spring) {
            panel = nil
            p.expanded = false
        }
    }

    private func open(_ newPanel: Panel) {
        withAnimation(Motion.spring) { panel = newPanel }
    }

    /// Swipe down to minimise, swipe up to go fullscreen. The page follows your finger.
    private var playerGesture: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .global)
            .onChanged { g in
                let dy = g.translation.height
                // Only vertical swipes; sideways drags belong to the seek bar.
                guard abs(dy) > abs(g.translation.width) else { return }
                if dy > 0 { drag = dy }
            }
            .onEnded { g in
                let dy = g.translation.height
                let predicted = g.predictedEndTranslation.height
                guard abs(dy) > abs(g.translation.width) else { drag = 0; return }
                if dy > 110 || predicted > 320 {
                    collapse()
                } else if dy < -70 || predicted < -260 {
                    withAnimation(Motion.spring) { fullscreen = true }
                }
                drag = 0
            }
    }

    private var fullscreenView: some View {
        ZStack(alignment: .trailing) {
            Color.black.ignoresSafeArea()
            PlayerArea(fullscreen: true, onCollapse: collapse, onSettings: { open(.settings) }, onFullscreen: { withAnimation(Motion.spring) { fullscreen = false } })
                .ignoresSafeArea()
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { g in
                            if g.translation.height > 80 { withAnimation(Motion.spring) { fullscreen = false } }
                        }
                )
            if let panel {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { withAnimation(Motion.spring) { self.panel = nil } }
                panelView(panel)
                    .frame(width: 400)
                    .frame(maxHeight: .infinity)
                    .modifier(PanelSurface(edges: .all))
                    .padding(.vertical, 10)
                    .padding(.trailing, 10)
                    .transition(.move(edge: .trailing))
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var portrait: some View {
        ZStack(alignment: .top) {
            Backdrop().ignoresSafeArea()
            if AppSettings.shared.d.ambient, let v = p.current {
                AmbientGlow(colors: p.ambient, fallback: v, strength: AppSettings.shared.d.ambientStrength, dark: t.dark)
                    .ignoresSafeArea()
            }
            VStack(spacing: 0) {
                PlayerArea(fullscreen: false, onCollapse: collapse, onSettings: { open(.settings) }, onFullscreen: { withAnimation(Motion.spring) { fullscreen = true } })
                    .simultaneousGesture(playerGesture)
                ZStack(alignment: .top) {
                    ScrollView {
                        if let v = p.current { content(v) }
                    }
                    .scrollIndicators(.hidden)
                    .modifier(SheetSurface())
                    .overlay(alignment: .top) {
                        // Grab area: drag the top of the page down to minimise.
                        Color.clear.frame(height: 34).contentShape(Rectangle())
                            .highPriorityGesture(playerGesture)
                    }
                    if let panel {
                        VStack(spacing: 0) {
                            panelHeader(panel)
                            panelView(panel)
                        }
                        .modifier(PanelSurface(edges: .top))
                        .transition(.move(edge: .bottom))
                        .zIndex(2)
                    }
                }
                .padding(.top, t.glass ? 8 : 0)
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private func panelHeader(_ panel: Panel) -> some View {
        VStack(spacing: 10) {
            Capsule().fill(t.ink3.opacity(0.6)).frame(width: 40, height: 5)
            HStack {
                Text(panel == .settings ? "More" : "Comments").font(.system(size: 22, weight: .bold)).foregroundStyle(t.ink)
                if panel == .comments, let c = p.details?.commentCount {
                    Text(c).font(.system(size: 17)).foregroundStyle(t.ink2)
                }
                Spacer()
                Button { withAnimation(Motion.spring) { self.panel = nil } } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(t.ink)
                        .frame(width: 40, height: 40)
                        .background(t.ink.opacity(0.08), in: Circle())
                }
                .buttonStyle(PressStyle())
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 6)
                .onEnded { g in
                    if g.translation.height > 40 || g.predictedEndTranslation.height > 120 {
                        withAnimation(Motion.spring) { self.panel = nil }
                    }
                }
        )
    }

    @ViewBuilder
    private func panelView(_ panel: Panel) -> some View {
        switch panel {
        case .settings: PlayerSettingsPanel(close: { withAnimation(Motion.spring) { self.panel = nil } })
        case .comments: CommentsPanel()
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
                    .transition(.opacity)
            }
            channelRow(v, d)
            actions(v, d)
            if let chapters = d?.chapters, !chapters.isEmpty { ChapterStrip(chapters: chapters) }
            commentsCard(d)
            if !p.queue.isEmpty { queueSection }
            if let related = d?.related, !related.isEmpty {
                CardLabel(text: "Up next")
                LazyVStack(spacing: 8) {
                    ForEach(related.filter { AppSettings.shared.allowed($0) }) { r in
                        VideoRow(video: r, thumbWidth: 168)
                    }
                }
            } else if d == nil {
                LoadingDots()
            }
        }
        .padding(.horizontal, 16)
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

    private func commentsCard(_ d: VideoDetails?) -> some View {
        Button { open(.comments) } label: {
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

/// Chapters row. Lives in its own view so only it updates as the video plays.
struct ChapterStrip: View {
    @Environment(\.theme) private var t
    var chapters: [Chapter]
    var p = PlayerModel.shared

    var body: some View {
        let currentIndex = chapters.lastIndex { $0.start <= p.time } ?? 0
        VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "Chapters")
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(chapters.enumerated()), id: \.element.id) { i, c in
                            Button { p.seek(c.start) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    if let th = c.thumbnail, let u = URL(string: th) {
                                        Color.clear.aspectRatio(16 / 9, contentMode: .fit)
                                            .overlay { RemoteImage(urls: [u], maxPixel: 320) }
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    Text(c.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(t.ink).lineLimit(1)
                                    Text(formatTime(c.start)).font(.system(size: 11)).foregroundStyle(t.ink2)
                                }
                                .padding(7)
                                .frame(width: 148)
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
}

private struct PanelSurface: ViewModifier {
    @Environment(\.theme) private var t
    var edges: Edge.Set
    func body(content: Content) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: edges == .all ? 28 : 0,
                                           bottomTrailingRadius: edges == .all ? 28 : 0, topTrailingRadius: 28, style: .continuous)
        content
            .background(t.dark ? Color(hex: 0x16171D).opacity(0.97) : Color(hex: 0xF6F6F9).opacity(0.98), in: shape)
            .overlay(shape.strokeBorder(t.dark ? Color.white.opacity(0.08) : Color.white, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 20, y: -4)
    }
}

private struct SheetSurface: ViewModifier {
    @Environment(\.theme) private var t
    private var ambientOn: Bool { AppSettings.shared.d.ambient }
    @ViewBuilder func body(content: Content) -> some View {
        if t.glass {
            content
                .background {
                    // The top of the sheet is see-through so ambient light from the video glows under the title.
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        Rectangle().fill(t.glassFillStrong)
                    }
                    .mask(LinearGradient(stops: [.init(color: .black.opacity(ambientOn ? 0.15 : 1), location: 0),
                                                 .init(color: .black, location: ambientOn ? 0.32 : 0)],
                                         startPoint: .top, endPoint: .bottom))
                }
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
    @State private var flash: String?

    var body: some View {
        ZStack {
            Color.black
            if p.audioOnly, let v = p.current {
                Thumbnail(video: v, radius: 0, large: true).overlay(Color.black.opacity(0.35))
                Image(systemName: "headphones").font(.system(size: 40, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
            } else {
                VideoSurface(main: true, gravity: fullscreen && AppSettings.shared.d.fillScreen ? .resizeAspectFill : .resizeAspect)
            }
            CaptionOverlay(fullscreen: fullscreen, raised: showControls)
            gestureLayer
            if let flash {
                Image(systemName: flash).font(.system(size: 32, weight: .bold)).foregroundStyle(.white)
                    .padding(20).background(.black.opacity(0.35), in: Circle())
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
            if p.locked {
                lockOverlay
            } else if showControls || p.loading || !p.isPlaying {
                controls.transition(.opacity)
            }
            if let e = p.error {
                VStack(spacing: 10) {
                    Text(e).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                    Button("Try again") { p.error = nil; p.reload() }
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 18).padding(.vertical, 10).background(.white, in: Capsule())
                }
                .padding(20)
            }
        }
        .aspectRatio(fullscreen ? nil : 16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: fullscreen ? .infinity : nil)
        .clipped()
        .onAppear { scheduleHide() }
        .statusBarHidden(fullscreen)
        .persistentSystemOverlays(fullscreen ? .hidden : .automatic)
    }

    private var lockOverlay: some View {
        Color.clear
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                Button { withAnimation(Motion.spring) { p.locked = false } } label: {
                    Label("Tap to unlock", systemImage: "lock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: Capsule())
                }
                .padding(12)
            }
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
        withAnimation(.easeInOut(duration: 0.18)) { showControls.toggle() }
        if showControls { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled, p.isPlaying else { return }
            withAnimation(.easeInOut(duration: 0.3)) { showControls = false }
        }
    }

    private var controls: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0.1), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    roundButton(fullscreen ? "chevron.down" : "chevron.down") {
                        if fullscreen { onFullscreen() } else { onCollapse() }
                    }
                    Spacer()
                    AutoplaySwitch { scheduleHide() }
                    roundButton(p.captionTrack == nil ? "captions.bubble" : "captions.bubble.fill") { p.toggleCaptions() }
                    roundButton("tv") { AppState.shared.showCast = true }
                    if p.pipPossible { roundButton("pip.enter") { p.startPiP() } }
                    roundButton("gearshape") { onSettings() }
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    transportButton("backward.end.fill", size: 22) { p.seek(0) }
                    transportButton("gobackward.10", size: 28) { p.skip(-10) }
                    Button { p.toggle(); scheduleHide() } label: {
                        ZStack {
                            if p.loading {
                                ProgressView().tint(.white).scaleEffect(1.3)
                            } else {
                                Image(systemName: p.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 32, weight: .bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(width: 74, height: 74)
                        .background(.black.opacity(0.35), in: Circle())
                    }
                    .buttonStyle(PressStyle())
                    .frame(maxWidth: .infinity)
                    transportButton("goforward.10", size: 28) { p.skip(10) }
                    transportButton("forward.end.fill", size: 22) { p.next() }
                }
                Spacer(minLength: 0)
                ScrubberRow(fullscreen: fullscreen, onFullscreen: onFullscreen, keepAwake: scheduleHide)
            }
            .padding(.horizontal, fullscreen ? 40 : 10)
            .padding(.vertical, fullscreen ? 20 : 8)
        }
    }

    private func transportButton(_ icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button { action(); scheduleHide() } label: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .frame(maxWidth: .infinity)
    }

    private func roundButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: { action(); scheduleHide() }) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.3), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
    }
}

private struct AutoplaySwitch: View {
    var onTap: () -> Void
    var settings = AppSettings.shared
    var body: some View {
        let on = settings.d.autoplay
        Button {
            settings.set(\.autoplay, !on)
            PlayerModel.shared.showToast(!on ? "Autoplay is on" : "Autoplay is off")
            onTap()
        } label: {
            Capsule()
                .fill(on ? Color.white : Color.white.opacity(0.3))
                .frame(width: 42, height: 24)
                .overlay(alignment: on ? .trailing : .leading) {
                    Image(systemName: on ? "play.fill" : "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(on ? .black : .white)
                        .frame(width: 20, height: 20)
                        .background(on ? Color.white : Color.black.opacity(0.5), in: Circle())
                        .padding(2)
                }
                .frame(width: 48, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Time, chapter name, seek bar. Separate so only this redraws while the video plays.
private struct ScrubberRow: View {
    var fullscreen: Bool
    var onFullscreen: () -> Void
    var keepAwake: () -> Void
    var p = PlayerModel.shared
    @State private var scrubbing: Double?

    private var chapter: String? {
        guard let chapters = p.details?.chapters, !chapters.isEmpty else { return nil }
        let at = scrubbing ?? p.time
        return chapters.last { $0.start <= at }?.title
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(formatTime(scrubbing ?? p.time) + " / " + formatTime(p.duration) + (chapter.map { " · \($0)" } ?? ""))
                    .lineLimit(1)
                Spacer()
                if let q = p.playingQuality {
                    Text(q.label).font(.system(size: 11, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                }
                Button(action: onFullscreen) {
                    Image(systemName: fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle())
                }
            }
            .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            SeekBar(time: p.time, duration: p.duration, chapters: p.details?.chapters ?? [], segments: p.segments, scrubbing: $scrubbing) { s in
                p.seek(s)
                keepAwake()
            }
        }
    }
}

private struct CaptionOverlay: View {
    var fullscreen: Bool
    var raised: Bool
    var p = PlayerModel.shared
    var body: some View {
        if let caption = p.captionText {
            VStack {
                Spacer()
                Text(caption)
                    .font(.system(size: fullscreen ? 20 : 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, raised ? 64 : 14)
                    .padding(.horizontal, 16)
            }
            .allowsHitTesting(false)
        }
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

// MARK: - Panels

struct CommentsPanel: View {
    @Environment(\.theme) private var t
    var p = PlayerModel.shared
    @State private var items: [Comment] = []
    @State private var next: String?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

/// Player "More" sheet, matching the Android app: quality, speed, captions, audio only,
/// sleep timer, ambient mode, fill screen, lock, data saver and autoplay.
/// Player "More" sheet, matching the Android app: quality, speed, captions, audio only,
/// sleep timer, ambient mode, fill screen, lock, data saver and autoplay.
struct PlayerSettingsPanel: View {
    @Environment(\.theme) private var t
    var close: () -> Void = {}
    var p = PlayerModel.shared
    var settings = AppSettings.shared

    private var qualityNote: String {
        let now = p.playingQuality.map { "Playing \($0.label)\($0.av1 ? " · AV1" : "")" } ?? (p.audioOnly ? "Audio only" : "Auto")
        let top = p.qualities.first.map { $0.label } ?? "—"
        return "\(now) · best on this iPhone: \(top)"
    }

    private var sleepLabel: String {
        if p.sleepAtEnd { return "End of video" }
        if let at = p.sleepAt { return "On · \(max(1, Int(at.timeIntervalSinceNow / 60))) min left" }
        return "Off"
    }

    var body: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            RowGroup(title: "Picture") {
                ChoiceRow(icon: "sparkles.rectangle.stack", title: "Quality",
                          note: qualityNote,
                          options: [("Auto", 0)] + (p.qualities.isEmpty ? [("1080p", 1080), ("720p", 720), ("480p", 480)] : p.qualities.map { ($0.label, $0.height) }),
                          selection: p.qualityCap ?? 0) { p.setQuality($0 == 0 ? nil : $0) }
                RowDivider(inset: 58)
                ChoiceRow(icon: "gauge.with.dots.needle.67percent", title: "Playback speed",
                          options: [Float(0.5), 0.75, 1, 1.25, 1.5, 1.75, 2].map { ($0 == 1 ? "Normal" : String(format: "%gx", $0), $0) },
                          selection: p.speed) { p.setSpeed($0) }
                RowDivider(inset: 58)
                captions
            }
            RowGroup(title: "Listening") {
                ToggleRow(icon: "headphones", title: "Audio only", note: "Plays just the sound: less data, less battery",
                          isOn: Binding(get: { p.audioOnly }, set: { p.setAudioOnly($0) }))
                RowDivider(inset: 58)
                ChoiceRow(icon: "moon.zzz", title: "Sleep timer", note: sleepLabel,
                          options: [("Off", -1), ("15 min", 15), ("30 min", 30), ("45 min", 45), ("60 min", 60), ("End of video", 0)],
                          selection: p.sleepChoice) { v in
                    if v == 0 { p.setSleepAtEnd() } else if v < 0 { p.setSleep(minutes: nil) } else { p.setSleep(minutes: v) }
                }
            }
            RowGroup(title: "Look") {
                ToggleRow(icon: "rays", title: "Ambient mode", note: "The video's colours glow softly around the player", isOn: settings.binding(\.ambient))
                if settings.d.ambient {
                    SliderRow(title: "Strength", valueLabel: "\(Int(settings.d.ambientStrength * 100))%", value: settings.binding(\.ambientStrength))
                }
                RowDivider(inset: 58)
                ToggleRow(icon: "arrow.up.left.and.arrow.down.right", title: "Fill screen in fullscreen", note: "Uses the whole display, around the camera too", isOn: settings.binding(\.fillScreen))
            }
            RowGroup(title: "More") {
                NavRow(icon: "lock", title: "Lock screen", note: "Ignore touches while you watch", chevron: false) {
                    p.locked = true
                    close()
                }
                RowDivider(inset: 58)
                ToggleRow(icon: "antenna.radiowaves.left.and.right", title: "Data saver", note: "Start videos at 480p",
                          isOn: Binding(get: { settings.d.dataSaver }, set: { settings.set(\.dataSaver, $0); p.setQuality($0 ? 480 : nil) }))
                RowDivider(inset: 58)
                ToggleRow(icon: "forward.end", title: "Autoplay next video", isOn: settings.binding(\.autoplay))
            }
          }
          .padding(.top, 4)
          .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var captions: some View {
        if p.captionTracks.isEmpty {
            NavRow(icon: "captions.bubble", title: "Captions", value: "None", chevron: false) {}
                .disabled(true)
        } else {
            ChoiceRow(icon: "captions.bubble", title: "Captions",
                      options: [("Off", "")] + p.captionTracks.map { ($0.auto && !$0.name.lowercased().contains("auto") ? "\($0.name) (auto)" : $0.name, $0.url) },
                      selection: p.captionTrack?.url ?? "") { url in
                p.selectCaption(p.captionTracks.first { $0.url == url })
            }
        }
    }
}

/// Soft coloured light from the video, behind the player (Android's ambient mode).
/// Built from radial gradients rather than a live blur, so it costs almost nothing to animate.
struct AmbientGlow: View {
    var colors: [Color]
    var fallback: Video
    var strength: Double
    var dark: Bool

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let k = (dark ? 0.9 : 0.75) * (0.3 + strength * 0.7)
            let c = colors.count == 4 ? colors : [Color(hex: 0x9B8CFF), Color(hex: 0x6FD3FF), Color(hex: 0xFF7EB3), Color(hex: 0x7EE8C1)]
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    RadialGradient(colors: [c[i].opacity(k), c[i].opacity(k * 0.35), .clear],
                                   center: .center, startRadius: 0, endRadius: w * 0.62)
                        .frame(width: w * 1.3, height: w * 1.3)
                        .offset(x: (i % 2 == 0 ? -1 : 1) * w * 0.3, y: (i < 2 ? -0.05 : 0.45) * w)
                }
            }
            .frame(width: w, height: w * 1.4, alignment: .top)
            .clipped()
            .opacity(colors.count == 4 ? 1 : 0)
            .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
        }
        .allowsHitTesting(false)
    }
}
