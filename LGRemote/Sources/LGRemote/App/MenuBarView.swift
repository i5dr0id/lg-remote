import AppKit
import LGTVKit
import SwiftUI

struct MenuBarView: View {
    @Environment(TVModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 14) {
            RemoteDisplay()

            HStack(spacing: 10) {
                Button { model.togglePower() } label: { Image(systemName: "power") }
                    .buttonStyle(.roundKey(RemotePalette.power))
                    .frame(width: 32, height: 32)
                Spacer()
                small("speaker.minus.fill", model.volumeDown)
                small(model.muted ? "speaker.slash.fill" : "speaker.slash", model.toggleMute)
                small("speaker.plus.fill", model.volumeUp)
            }

            DPad(diameter: 132)

            HStack(spacing: 10) {
                small("arrow.uturn.backward") { model.press(.back) }
                small("house.fill") { model.press(.home) }
                small("gearshape.fill") { model.press(.menu) }
                Spacer()
                small("play.fill") { model.press(.play) }
                small("pause.fill") { model.press(.pause) }
            }

            Divider()

            VStack(spacing: 2) {
                row("Open Remote", symbol: "av.remote") {
                    openWindow(id: WindowID.remote)
                    NSApp.activate()
                }
                SettingsLink {
                    Label("Settings…", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(MenuRowStyle())
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
                row("Quit LG Remote", symbol: "xmark.circle") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 250)
        .background(RemotePalette.bodyBottom)
        .environment(\.colorScheme, .dark)
    }

    private func small(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11)) }
            .buttonStyle(.roundKey)
            .frame(width: 30, height: 30)
    }

    private func row(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MenuRowStyle())
    }
}

private struct MenuRowStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(RemotePalette.label)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(configuration.isPressed ? 0.18 : hovering ? 0.1 : 0)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
