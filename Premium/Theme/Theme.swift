import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// The four looks the app can wear. Pearl Glass is the default on iOS.
enum ThemeKind: String, Codable, CaseIterable, Identifiable {
    case pearl, classic, daylight, midnight
    var id: String { rawValue }

    var title: String {
        switch self {
        case .pearl: return "Pearl Glass"
        case .classic: return "Classic"
        case .daylight: return "Daylight"
        case .midnight: return "Midnight Glass"
        }
    }

    var subtitle: String {
        switch self {
        case .pearl: return "Default"
        case .classic: return "From your Figma kit"
        case .daylight: return "Red & white"
        case .midnight: return "Dark"
        }
    }
}

/// Rainbow edge colours from the Pearl Glass spec.
let rainbow: [Color] = [
    Color(hex: 0xFF7EB3), Color(hex: 0xFFC07A), Color(hex: 0x7EE8C1),
    Color(hex: 0x6FD3FF), Color(hex: 0x9B8CFF), Color(hex: 0xFF7EB3)
]

struct Theme {
    var kind: ThemeKind
    var dark: Bool
    /// Glass surfaces (Pearl, Daylight, Midnight) or flat cards (Classic).
    var glass: Bool

    var ink: Color
    var ink2: Color
    var ink3: Color

    var bgTop: Color
    var bgBottom: Color
    var blobs: [Color]
    var blobOpacity: Double

    var glassFill: Color
    var glassFillStrong: Color
    var strokeTop: Color
    var strokeBottom: Color
    var shadow: Color

    var card: Color
    var divider: Color

    /// Selected chip, primary buttons.
    var accent: Color
    var onAccent: Color
    /// Subscribe button.
    var subscribe: Color
    var onSubscribe: Color
    /// Progress bars and the seek bar.
    var progress: Color

    var success = Color(hex: 0x34C79A)
    var warning = Color(hex: 0xF2A541)
    var danger = Color(hex: 0xF0566B)

    var usesGreeting: Bool { kind != .classic }

    static func make(_ kind: ThemeKind, evening: Bool) -> Theme {
        switch kind {
        case .pearl where evening:
            var t = midnight
            t.kind = .pearl
            return t
        case .pearl: return pearl
        case .classic: return classic
        case .daylight: return daylight
        case .midnight: return midnight
        }
    }

    static let pearl = Theme(
        kind: .pearl, dark: false, glass: true,
        ink: Color(hex: 0x1C1D24), ink2: Color(hex: 0x6B6E7B), ink3: Color(hex: 0xA3A6B2),
        bgTop: Color(hex: 0xECEDF3), bgBottom: Color(hex: 0xF7F5F9),
        blobs: [Color(hex: 0xD9D3F3), Color(hex: 0xCFE3F5), Color(hex: 0xF3D9E4), Color(hex: 0xD5EEE6)],
        blobOpacity: 0.75,
        glassFill: .white.opacity(0.55), glassFillStrong: .white.opacity(0.80),
        strokeTop: .white.opacity(0.85), strokeBottom: .white.opacity(0.25),
        shadow: Color(hex: 0x3C405A, opacity: 0.12),
        card: Color(hex: 0xF4F4F7), divider: Color(hex: 0x1C1D24, opacity: 0.06),
        accent: Color(hex: 0x1C1D24), onAccent: .white,
        subscribe: Color(hex: 0x1C1D24), onSubscribe: .white,
        progress: Color(hex: 0x1C1D24))

    static let classic = Theme(
        kind: .classic, dark: false, glass: false,
        ink: Color(hex: 0x0F0F0F), ink2: Color(hex: 0x606060), ink3: Color(hex: 0x909090),
        bgTop: .white, bgBottom: .white,
        blobs: [.clear, .clear, .clear, .clear], blobOpacity: 0,
        glassFill: .white, glassFillStrong: .white,
        strokeTop: .clear, strokeBottom: .clear, shadow: .clear,
        card: Color(hex: 0xF2F2F2), divider: Color(hex: 0x000000, opacity: 0.1),
        accent: Color(hex: 0x0F0F0F), onAccent: .white,
        subscribe: Color(hex: 0xFF0000), onSubscribe: .white,
        progress: Color(hex: 0xFF0000))

    static let daylight = Theme(
        kind: .daylight, dark: false, glass: true,
        ink: Color(hex: 0x1A1A1A), ink2: Color(hex: 0x6E6E6E), ink3: Color(hex: 0xA8A8A8),
        bgTop: .white, bgBottom: Color(hex: 0xFFF3F3),
        blobs: [Color(hex: 0xFFE1E1), Color(hex: 0xFFF0E6), Color(hex: 0xFFE6EC), Color(hex: 0xFFF5F5)],
        blobOpacity: 0.8,
        glassFill: .white.opacity(0.65), glassFillStrong: .white.opacity(0.88),
        strokeTop: .white.opacity(0.9), strokeBottom: Color(hex: 0xFFD6D6, opacity: 0.5),
        shadow: Color(hex: 0xB03030, opacity: 0.10),
        card: .white, divider: Color(hex: 0xE52222, opacity: 0.10),
        accent: Color(hex: 0xE52222), onAccent: .white,
        subscribe: Color(hex: 0xE52222), onSubscribe: .white,
        progress: Color(hex: 0xE52222))

    static let midnight = Theme(
        kind: .midnight, dark: true, glass: true,
        ink: .white, ink2: .white.opacity(0.62), ink3: .white.opacity(0.38),
        bgTop: Color(hex: 0x0E0F14), bgBottom: Color(hex: 0x12131A),
        blobs: [Color(hex: 0x3B2E7A), Color(hex: 0x164E5A), Color(hex: 0x3B2E7A), Color(hex: 0x164E5A)],
        blobOpacity: 0.45,
        glassFill: .black.opacity(0.35), glassFillStrong: .black.opacity(0.5),
        strokeTop: .white.opacity(0.18), strokeBottom: .white.opacity(0.04),
        shadow: .black.opacity(0.35),
        card: Color(hex: 0x1B1C23), divider: .white.opacity(0.08),
        accent: .white, onAccent: Color(hex: 0x0E0F14),
        subscribe: .white, onSubscribe: Color(hex: 0x0E0F14),
        progress: .white)
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.pearl
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

enum Motion {
    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.82)
    static let press = Animation.spring(response: 0.25, dampingFraction: 0.6)
}
