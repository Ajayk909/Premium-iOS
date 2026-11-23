import SwiftUI

/// Floating glass tab bar with a sliding white pill (glass themes) or a flat bar (Classic).
struct TabBar: View {
    @Environment(\.theme) private var t
    @Namespace private var ns
    var state = AppState.shared

    var body: some View {
        if t.glass { glassBar } else { flatBar }
    }

    private var glassBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                let on = state.tab == tab
                Button { state.select(tab) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: on ? tab.iconOn : tab.icon).font(.system(size: 19, weight: .semibold))
                        Text(tab.title).font(.system(size: 10.5, weight: on ? .bold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(on ? t.ink : t.ink2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background {
                        if on {
                            Capsule()
                                .fill(t.dark ? Color.white.opacity(0.16) : Color.white)
                                .shadow(color: Color(hex: 0x3C405A, opacity: t.dark ? 0 : 0.14), radius: 8, y: 4)
                                .matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(6)
        .surface(32)
        .padding(.horizontal, 20)
        .animation(Motion.spring, value: state.tab)
        .sensoryFeedback(.selection, trigger: state.tab)
    }

    private var flatBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(t.divider).frame(height: 0.5)
            HStack(spacing: 0) {
                ForEach(Tab.allCases) { tab in
                    let on = state.tab == tab
                    Button { state.select(tab) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: on ? tab.iconOn : tab.icon).font(.system(size: 21))
                            Text(tab.title).font(.system(size: 10, weight: on ? .medium : .regular))
                        }
                        .foregroundStyle(t.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color.white.ignoresSafeArea(edges: .bottom))
        .sensoryFeedback(.selection, trigger: state.tab)
    }
}

/// Mini player that floats above the tab bar. Tap or swipe up to open, swipe down to close.
struct MiniPlayer: View {
    @Environment(\.theme) private var t
    var p = PlayerModel.shared
    @State private var drag: CGFloat = 0

    var body: some View {
        if let v = p.current {
            HStack(spacing: 10) {
                ZStack {
                    if p.audioOnly || p.loading {
                        Thumbnail(video: v, radius: 0)
                    } else {
                        VideoSurface(main: false, gravity: .resizeAspectFill)
                    }
                }
                .frame(width: 84, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: t.glass ? 12 : 0, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(v.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(t.ink).lineLimit(1)
                    Text(v.channel).font(.system(size: 11.5)).foregroundStyle(t.ink2).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button { p.toggle() } label: {
                    Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(t.ink)
                        .frame(width: 40, height: 40)
                        .background(t.glass ? AnyShapeStyle(t.dark ? Color.white.opacity(0.15) : Color.white) : AnyShapeStyle(Color.clear), in: Circle())
                }
                .buttonStyle(PressStyle())
                Button { p.close() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(t.ink2).frame(width: 30, height: 40)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, t.glass ? 7 : 0)
            .padding(.trailing, 8)
            .frame(height: t.glass ? 62 : 56)
            .overlay(alignment: .bottom) {
                ProgressLine(value: p.duration > 0 ? p.time / p.duration : 0, height: 2.5)
                    .padding(.horizontal, t.glass ? 16 : 0)
            }
            .modifier(MiniSurface())
            .padding(.horizontal, t.glass ? 20 : 0)
            .offset(y: max(-30, drag))
            .opacity(1 - Double(max(0, drag)) / 160)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Motion.spring) { p.expanded = true } }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { drag = $0.translation.height }
                    .onEnded { g in
                        if g.translation.height > 60 || g.predictedEndTranslation.height > 140 {
                            p.close()
                        } else if g.translation.height < -40 {
                            withAnimation(Motion.spring) { p.expanded = true }
                        }
                        withAnimation(Motion.spring) { drag = 0 }
                    }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct MiniSurface: ViewModifier {
    @Environment(\.theme) private var t
    @ViewBuilder func body(content: Content) -> some View {
        if t.glass {
            content.surface(22, strong: true)
        } else {
            content.background(Color.white).overlay(alignment: .top) { Rectangle().fill(t.divider).frame(height: 0.5) }
        }
    }
}

struct Toast: View {
    @Environment(\.theme) private var t
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(t.onAccent)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(t.accent.opacity(0.92), in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}
