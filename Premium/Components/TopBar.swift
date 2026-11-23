import SwiftUI

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Plain reference box so tracking the scroll position doesn't redraw the page every frame.
private final class ScrollMemo {
    var last: CGFloat = 0
}

/// A scrolling page with YouTube's top bar: it slides away when you scroll down
/// and comes straight back when you scroll up, so search is always one flick away.
struct TopBarPage<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: () -> Content
    @State private var hidden = false
    @State private var memo = ScrollMemo()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 0)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: ScrollOffsetKey.self, value: g.frame(in: .named("page")).minY)
                    })
                content()
            }
            .padding(.top, 58)
        }
        .coordinateSpace(name: "page")
        .scrollIndicators(.hidden)
        .onPreferenceChange(ScrollOffsetKey.self) { y in track(y) }
        .overlay(alignment: .top) {
            AppTopBar(title: title)
                .offset(y: hidden ? -140 : 0)
                .animation(.easeOut(duration: 0.22), value: hidden)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func track(_ y: CGFloat) {
        let delta = y - memo.last
        if y > -40 {
            if hidden { hidden = false }
            memo.last = y
        } else if delta < -28 {
            if !hidden { hidden = true }
            memo.last = y
        } else if delta > 28 {
            if hidden { hidden = false }
            memo.last = y
        }
    }
}

struct AppTopBar: View {
    @Environment(\.theme) private var t
    var title: String?

    var body: some View {
        HStack(spacing: 2) {
            if let title {
                Text(title).font(.system(size: 24, weight: .bold)).tracking(-0.4).foregroundStyle(t.ink)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(t.kind == .classic || t.kind == .daylight ? Color.red : t.ink)
                    Text("Premium").font(.system(size: 21, weight: .bold)).tracking(-0.8).foregroundStyle(t.ink)
                }
            }
            Spacer()
            barButton("tv") { AppState.shared.showCast = true }
            barButton("magnifyingglass") { AppState.shared.push(.search(nil)) }
            barButton(GoogleAccount.shared.signedIn ? "person.crop.circle.fill" : "person.crop.circle") { AppState.shared.push(.settings) }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 52)
        .background {
            Group {
                if t.glass {
                    Rectangle().fill(.ultraThinMaterial).overlay(t.glassFill)
                } else {
                    Rectangle().fill(Color.white)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    private func barButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(t.ink)
                .frame(width: 46, height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}
