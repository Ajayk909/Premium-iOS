import SwiftUI

/// Cast to Roku + a full remote, in the Pearl Glass remote style.
struct CastSheet: View {
    @Environment(\.theme) private var t
    @Environment(\.dismiss) private var dismiss
    var roku = Roku.shared
    var p = PlayerModel.shared
    @State private var manualIP = ""
    @State private var showDevices = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Capsule().fill(t.ink3.opacity(0.6)).frame(width: 40, height: 5).padding(.top, 10)
                header
                if roku.current == nil || showDevices {
                    deviceList
                } else {
                    if let v = p.current { nowCard(v) }
                    remote
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background { Backdrop().ignoresSafeArea() }
        .onAppear { if roku.current == nil { roku.scan() } }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                CardLabel(text: roku.current == nil ? "Cast" : "Casting to")
                Text(roku.current?.name ?? "Find your TV").font(.system(size: 26, weight: .bold)).tracking(-0.3).foregroundStyle(t.ink).lineLimit(1)
            }
            Spacer()
            if roku.current != nil {
                Button { withAnimation(Motion.spring) { showDevices.toggle() } } label: {
                    HStack(spacing: 6) {
                        Circle().fill(t.success).frame(width: 7, height: 7)
                        Text(showDevices ? "Remote" : "Change").font(.system(size: 13, weight: .semibold)).foregroundStyle(t.ink)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .surface(16)
                }
                .buttonStyle(PressStyle())
            }
        }
    }

    private var deviceList: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                ForEach(roku.devices) { d in
                    Button {
                        roku.select(d)
                        withAnimation(Motion.spring) { showDevices = false }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "tv").font(.system(size: 17, weight: .semibold)).foregroundStyle(t.ink).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(t.ink)
                                Text(d.ip).font(.system(size: 12)).foregroundStyle(t.ink2)
                            }
                            Spacer()
                            if roku.current == d { Image(systemName: "checkmark").foregroundStyle(t.ink) }
                        }
                        .padding(.horizontal, 16).frame(height: 60)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if roku.devices.isEmpty {
                    HStack(spacing: 12) {
                        if roku.scanning { ProgressView() } else { Image(systemName: "wifi").foregroundStyle(t.ink2) }
                        Text(roku.scanning ? "Looking for Roku TVs on your Wi-Fi…" : (roku.lastError ?? "No TVs found yet."))
                            .font(.system(size: 14)).foregroundStyle(t.ink2)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .surface(24)

            Button { roku.scan() } label: {
                Label(roku.scanning ? "Scanning…" : "Scan again", systemImage: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(t.ink)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .surface(24, strong: true)
            }
            .buttonStyle(PressStyle())
            .disabled(roku.scanning)

            VStack(alignment: .leading, spacing: 8) {
                CardLabel(text: "Or type the TV's IP address")
                HStack {
                    TextField("192.168.1.20", text: $manualIP).keyboardType(.decimalPad).foregroundStyle(t.ink)
                    Button("Connect") { roku.addManual(manualIP) }.font(.system(size: 14, weight: .semibold)).disabled(manualIP.isEmpty)
                }
                .padding(.horizontal, 14).frame(height: 46).surface(23, strong: true)
                Text("On the Roku: Settings → Network → About shows the IP address.")
                    .font(.system(size: 12)).foregroundStyle(t.ink3)
            }
            .padding(.top, 6)
        }
    }

    private func nowCard(_ v: Video) -> some View {
        HStack(spacing: 12) {
            Thumbnail(video: v, radius: 12).frame(width: 100)
            VStack(alignment: .leading, spacing: 6) {
                Text(v.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(t.ink).lineLimit(2)
                Button {
                    roku.cast(v.id, at: p.time)
                    p.pause()
                    p.showToast("Playing on \(roku.current?.name ?? "TV")")
                } label: {
                    Label("Play on TV", systemImage: "tv")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(t.onAccent)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(t.accent, in: Capsule())
                }
                .buttonStyle(PressStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .surface(22)
    }

    private var remote: some View {
        VStack(spacing: 18) {
            HStack {
                roundKey("arrow.uturn.backward", "Back") { roku.key("Back") }
                Spacer()
                roundKey("house", "Home") { roku.key("Home") }
                Spacer()
                roundKey("power", "Power", tint: t.danger) { roku.key("Power") }
            }
            .padding(.horizontal, 8)

            DPad { roku.key($0) }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    capsuleKey("backward.fill") { roku.key("Rev") }
                    capsuleKey("playpause.fill", prominent: true) { roku.key("Play") }
                    capsuleKey("forward.fill") { roku.key("Fwd") }
                }
                HStack(spacing: 10) {
                    capsuleKey("speaker.slash.fill") { roku.key("VolumeMute") }
                    capsuleKey("minus") { roku.key("VolumeDown") }
                    capsuleKey("plus") { roku.key("VolumeUp") }
                }
                HStack(spacing: 10) {
                    capsuleKey("arrow.counterclockwise") { roku.key("InstantReplay") }
                    capsuleKey("asterisk") { roku.key("Info") }
                    capsuleKey("magnifyingglass") { roku.key("Search") }
                }
            }
        }
    }

    private func roundKey(_ icon: String, _ label: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(tint ?? t.ink)
                    .frame(width: 58, height: 58).surface(29)
                Text(label).font(.system(size: 12)).foregroundStyle(t.ink2)
            }
        }
        .buttonStyle(PressStyle())
    }

    private func capsuleKey(_ icon: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(t.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background { if prominent { Capsule().fill(t.dark ? Color.white.opacity(0.2) : .white).shadow(color: t.shadow, radius: 10, y: 6) } }
                .modifier(KeySurface(on: !prominent))
        }
        .buttonStyle(PressStyle())
    }
}

private struct KeySurface: ViewModifier {
    var on: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if on { content.surface(25) } else { content }
    }
}

/// Big glass disc with arrows and a white OK button that lights up with the rainbow ring.
struct DPad: View {
    @Environment(\.theme) private var t
    var send: (String) -> Void
    @State private var okPressed = false

    var body: some View {
        ZStack {
            Circle().fill(.clear).frame(width: 250, height: 250).surface(125)
            arrow("chevron.up", "Up").offset(y: -92)
            arrow("chevron.down", "Down").offset(y: 92)
            arrow("chevron.left", "Left").offset(x: -92)
            arrow("chevron.right", "Right").offset(x: 92)
            Button { send("Select") } label: {
                Text("OK").font(.system(size: 21, weight: .bold)).foregroundStyle(t.ink)
                    .frame(width: 96, height: 96)
                    .background(t.dark ? Color.white.opacity(0.18) : .white, in: Circle())
                    .shadow(color: t.shadow, radius: 14, y: 8)
                    .rainbowCircle(on: okPressed, width: 2.5)
            }
            .buttonStyle(OKStyle(pressed: $okPressed))
        }
        .frame(height: 260)
    }

    private func arrow(_ icon: String, _ key: String) -> some View {
        Button { send(key) } label: {
            Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(t.ink2)
                .frame(width: 64, height: 64).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

private struct OKStyle: ButtonStyle {
    @Binding var pressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, v in pressed = v }
    }
}
