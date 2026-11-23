import SwiftUI

/// Glass sheet with a grab handle and a big title. Used for every sheet so they all match the theme.
struct GlassSheet<Content: View>: View {
    @Environment(\.theme) private var t
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Capsule().fill(t.ink3.opacity(0.6)).frame(width: 40, height: 5).frame(maxWidth: .infinity).padding(.top, 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 26, weight: .bold)).tracking(-0.3).foregroundStyle(t.ink)
                    if let subtitle { Text(subtitle).font(.system(size: 14)).foregroundStyle(t.ink2) }
                }
                .padding(.horizontal, 22)
                content()
            }
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background { Backdrop().ignoresSafeArea() }
        .presentationBackground(.clear)
        .presentationCornerRadius(30)
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(t.dark ? .dark : .light)
    }
}

/// A titled glass card that holds rows.
struct RowGroup<Content: View>: View {
    @Environment(\.theme) private var t
    var title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { CardLabel(text: title).padding(.horizontal, 24) }
            VStack(spacing: 0) { content() }
                .modifier(ListCard())
        }
    }
}

struct RowDivider: View {
    @Environment(\.theme) private var t
    var inset: CGFloat = 16
    var body: some View { Rectangle().fill(t.divider).frame(height: 1).padding(.leading, inset) }
}

private struct RowIcon: View {
    @Environment(\.theme) private var t
    var name: String
    var tint: Color?
    var body: some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint ?? t.ink)
            .frame(width: 30, height: 30)
            .background(t.dark ? Color.white.opacity(0.1) : Color.white.opacity(t.glass ? 0.9 : 1), in: Circle())
    }
}

extension Theme {
    /// Toggle track colour: ink on light themes, soft violet on dark ones so the white knob stays visible.
    var toggleTint: Color { dark ? Color(hex: 0x8A7CF0) : accent }
}

struct ToggleRow: View {
    @Environment(\.theme) private var t
    var icon: String? = nil
    var title: String
    var note: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                if let icon { RowIcon(name: icon, tint: nil) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15.5, weight: .medium)).foregroundStyle(t.ink)
                    if let note { Text(note).font(.system(size: 12)).foregroundStyle(t.ink2) }
                }
            }
        }
        .tint(t.toggleTint)
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
    }
}

struct NavRow: View {
    @Environment(\.theme) private var t
    var icon: String? = nil
    var title: String
    var note: String? = nil
    var value: String? = nil
    var tint: Color? = nil
    var chevron = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon { RowIcon(name: icon, tint: tint) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15.5, weight: .medium)).foregroundStyle(tint ?? t.ink)
                    if let note { Text(note).font(.system(size: 12)).foregroundStyle(t.ink2).multilineTextAlignment(.leading) }
                }
                Spacer(minLength: 8)
                if let value { Text(value).font(.system(size: 14)).foregroundStyle(t.ink2).lineLimit(1) }
                if chevron { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(t.ink3) }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A row with a title and a strip of choice chips underneath.
struct ChoiceRow<Value: Hashable>: View {
    @Environment(\.theme) private var t
    var icon: String? = nil
    var title: String
    var note: String? = nil
    var options: [(String, Value)]
    var selection: Value
    var onSelect: (Value) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let icon { RowIcon(name: icon, tint: nil) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15.5, weight: .medium)).foregroundStyle(t.ink)
                    if let note { Text(note).font(.system(size: 12)).foregroundStyle(t.ink2) }
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                        let on = o.1 == selection
                        Button { onSelect(o.1) } label: {
                            Text(o.0)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(on ? t.onAccent : t.ink)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7)
                                .background(on ? AnyShapeStyle(t.accent) : AnyShapeStyle(t.ink.opacity(0.07)), in: Capsule())
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct SliderRow: View {
    @Environment(\.theme) private var t
    var icon: String? = nil
    var title: String
    var valueLabel: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let icon { RowIcon(name: icon, tint: nil) }
                Text(title).font(.system(size: 15.5, weight: .medium)).foregroundStyle(t.ink)
                Spacer()
                Text(valueLabel).font(.system(size: 13.5, weight: .semibold).monospacedDigit()).foregroundStyle(t.ink2)
            }
            Slider(value: $value, in: 0...1)
                .tint(t.toggleTint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
