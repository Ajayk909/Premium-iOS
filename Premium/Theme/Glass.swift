import SwiftUI

/// Every card, bar and sheet goes through this. Glass themes get the Pearl recipe
/// (material + tint + lit-from-above border + soft shadow); Classic gets a flat card.
struct Surface: ViewModifier {
    @Environment(\.theme) private var t
    @Environment(\.accessibilityReduceTransparency) private var noGlass
    var radius: CGFloat
    var strong: Bool
    /// Floating chrome (tab bar, mini player, pinned buttons) gets real blur and a shadow.
    /// Cards inside scrolling lists get a cheap tinted fill so scrolling stays at full frame rate.
    var chrome: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if t.glass && !noGlass && !chrome {
            content
                .background(t.dark ? Color.white.opacity(strong ? 0.10 : 0.07) : Color.white.opacity(strong ? 0.85 : 0.6), in: shape)
                .overlay(shape.strokeBorder(t.dark ? Color.white.opacity(0.08) : Color.white.opacity(0.9), lineWidth: 1))
        } else if t.glass && !noGlass {
            content
                .background(strong ? t.glassFillStrong : t.glassFill, in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(colors: [t.strokeTop, t.strokeBottom], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                )
                .shadow(color: t.shadow, radius: 15, x: 0, y: 10)
        } else if t.glass {
            content
                .background(t.dark ? Color(hex: 0x1B1C23) : Color(hex: 0xF4F4F7), in: shape)
                .overlay(shape.strokeBorder(t.dark ? Color.white.opacity(0.1) : Color(hex: 0xE2E3EA), lineWidth: 1))
        } else {
            content.background(strong ? Color.white : t.card, in: shape)
        }
    }
}

extension View {
    func surface(_ radius: CGFloat = 26, strong: Bool = false, chrome: Bool = false) -> some View {
        modifier(Surface(radius: radius, strong: strong, chrome: chrome))
    }

    /// Thin rainbow border used for focus, "now playing" and the selected item.
    func rainbowEdge(_ radius: CGFloat, on: Bool = true, width: CGFloat = 1.6) -> some View {
        overlay {
            if on {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(AngularGradient(colors: rainbow, center: .center), lineWidth: width)
            }
        }
    }

    func rainbowCircle(on: Bool = true, width: CGFloat = 2) -> some View {
        overlay {
            if on {
                Circle().strokeBorder(AngularGradient(colors: rainbow, center: .center), lineWidth: width)
            }
        }
    }

    /// Backdrop behind a whole screen.
    func screenBackground() -> some View {
        background { Backdrop().ignoresSafeArea() }
    }
}

/// Soft silk background: base gradient + blurred colour blobs + a faint rainbow light leak.
/// The blobs are drawn once per theme into a small picture and scaled up, so they cost nothing per frame.
struct Backdrop: View {
    @Environment(\.theme) private var t

    var body: some View {
        ZStack {
            LinearGradient(colors: [t.bgTop, t.bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            if t.blobOpacity > 0, let img = BackdropCache.image(for: t) {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.medium)
            }
        }
        .allowsHitTesting(false)
    }
}

enum BackdropCache {
    private static var store: [String: UIImage] = [:]

    @MainActor
    static func image(for t: Theme) -> UIImage? {
        let key = "\(t.kind.rawValue)-\(t.dark)"
        if let img = store[key] { return img }
        let renderer = ImageRenderer(content: BlobLayer(t: t).frame(width: 180, height: 390))
        renderer.scale = 1
        let img = renderer.uiImage
        store[key] = img
        return img
    }
}

private struct BlobLayer: View {
    var t: Theme
    var body: some View {
        ZStack {
            Color.clear
            blob(0, x: -0.35, y: -0.30)
            blob(1, x: 0.45, y: 0.05)
            blob(2, x: -0.40, y: 0.42)
            blob(3, x: 0.40, y: 0.50)
            LinearGradient(colors: rainbow, startPoint: .leading, endPoint: .trailing)
                .frame(width: 240, height: 70)
                .rotationEffect(.degrees(-35))
                .blur(radius: 30)
                .opacity(t.dark ? 0.08 : 0.13)
                .offset(x: 180 * 0.42, y: -390 * 0.33)
        }
        .frame(width: 180, height: 390)
        .clipped()
    }

    private func blob(_ i: Int, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(t.blobs[i])
            .frame(width: 175, height: 175)
            .blur(radius: 38)
            .opacity(t.blobOpacity)
            .offset(x: 180 * x, y: 390 * y)
    }
}

/// Press feedback: scale to 0.96 with a quick spring.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Round glass icon button.
struct GlassIcon: View {
    @Environment(\.theme) private var t
    var system: String
    var size: CGFloat = 44
    var tint: Color? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint ?? t.ink)
                .frame(width: size, height: size)
                .surface(size / 2, chrome: true)
        }
        .buttonStyle(PressStyle())
    }
}

/// Capsule chip; the selected one is solid.
struct Chip: View {
    @Environment(\.theme) private var t
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? t.onAccent : t.ink)
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .background {
                    if selected {
                        Capsule().fill(t.accent).shadow(color: t.accent.opacity(0.25), radius: 8, y: 4)
                    }
                }
                .modifier(ChipSurface(selected: selected))
        }
        .buttonStyle(PressStyle())
    }
}

private struct ChipSurface: ViewModifier {
    var selected: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if selected { content } else { content.surface(20) }
    }
}

/// Tiny uppercase label for cards.
struct CardLabel: View {
    @Environment(\.theme) private var t
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(t.ink2)
    }
}

/// Two-line greeting header: line two is faded.
struct Greeting: View {
    @Environment(\.theme) private var t
    var line1: String
    var line2: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(line1).foregroundStyle(t.ink)
            Text(line2).foregroundStyle(t.ink3)
        }
        .font(.system(size: 32, weight: .bold))
        .tracking(-0.4)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

struct ProgressLine: View {
    @Environment(\.theme) private var t
    var value: Double
    var height: CGFloat = 3
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(t.ink.opacity(0.12))
                Capsule().fill(t.progress).frame(width: max(0, min(1, value)) * g.size.width)
            }
        }
        .frame(height: height)
    }
}
