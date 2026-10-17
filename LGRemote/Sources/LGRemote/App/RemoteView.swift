import AppKit
import LGTVKit
import SwiftUI

struct RemoteView: View {
    @Environment(TVModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @FocusState private var focused: Bool
    @State private var hovering = false
    @State private var popover: Popover?

    enum Popover: Identifiable {
        case numbers, apps, keyboard, touchpad
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            RemoteDisplay()
            rockers
            DPad()
            navigationRow
            mediaRow
            colorRow
            appRow
            Text("webOS")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(3)
                .foregroundStyle(RemotePalette.secondaryLabel)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 22)
        .frame(width: 252)
        .background(remoteBody)
        .overlay(alignment: .topLeading) { closeButton }
        .padding(18) // room for the drop shadow inside the transparent window
        .containerBackground(.clear, for: .window)
        .onHover { hovering = $0 }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: [.down, .repeat], action: handleKey)
        .onAppear {
            focused = true
            NSApp.activate()
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Button { model.togglePower() } label: { Image(systemName: "power") }
                .buttonStyle(.roundKey(RemotePalette.power, fontSize: 15))
                .frame(width: 38, height: 38)
                .help("Power (off when connected, Wake-on-LAN when not)")
            Spacer()
            StatusLight()
            Spacer()
            Menu {
                if model.inputs.isEmpty {
                    Text(model.isConnected ? "No inputs found" : "Not connected")
                }
                ForEach(model.inputs) { input in
                    Button(input.label + (input.connected ? "" : " (not connected)")) { model.switchInput(input.id) }
                }
                Divider()
                Button("Refresh") { Task { await model.refreshLists() } }
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.roundKey)
            .frame(width: 38, height: 38)
            .help("Input")
        }
    }

    private var rockers: some View {
        HStack {
            Rocker(title: "VOL", upSymbol: "plus", downSymbol: "minus", up: model.volumeUp, down: model.volumeDown)
                .frame(width: 50, height: 124)
            Spacer()
            VStack(spacing: 10) {
                Button { model.toggleMute() } label: {
                    Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.slash")
                }
                .buttonStyle(.roundKey)
                .frame(width: 34, height: 34)
                .help("Mute")
                popoverKey("123", .numbers, help: "Number pad")
                popoverKey("square.grid.2x2.fill", .apps, symbol: true, help: "Apps")
            }
            Spacer()
            Rocker(title: "CH", upSymbol: "chevron.up", downSymbol: "chevron.down", up: model.channelUp, down: model.channelDown)
                .frame(width: 50, height: 124)
        }
    }

    private var navigationRow: some View {
        HStack {
            key("arrow.uturn.backward", help: "Back") { model.press(.back) }
            Spacer()
            key("house.fill", help: "Home") { model.press(.home) }
            Spacer()
            key("gearshape.fill", help: "TV settings") { model.press(.menu) }
            Spacer()
            popoverKey("keyboard", .keyboard, symbol: true, help: "Type text", size: 36)
        }
    }

    private var mediaRow: some View {
        HStack(spacing: 8) {
            mediaKey("backward.fill", .rewind)
            mediaKey("play.fill", .play)
            mediaKey("pause.fill", .pause)
            mediaKey("stop.fill", .stop)
            mediaKey("forward.fill", .fastForward)
        }
    }

    private var colorRow: some View {
        HStack(spacing: 8) {
            colorKey(.red, .red)
            colorKey(.green, .green)
            colorKey(.yellow, .yellow)
            colorKey(.blue, .blue)
        }
    }

    private var appRow: some View {
        HStack(spacing: 8) {
            appKey("YouTube", id: "youtube.leanback.v4", color: Color(red: 0.75, green: 0.08, blue: 0.08))
            appKey("Netflix", id: "netflix", color: Color(red: 0.45, green: 0.03, blue: 0.05))
            popoverKey("cursorarrow.motionlines", .touchpad, symbol: true, help: "Touchpad", size: 28)
        }
    }

    private var remoteBody: some View {
        RoundedRectangle(cornerRadius: 46, style: .continuous)
            .fill(LinearGradient(colors: [RemotePalette.bodyTop, RemotePalette.bodyBottom], startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: 46, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
    }

    private var closeButton: some View {
        Button { dismissWindow(id: WindowID.remote) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.roundKey(Color(white: 0.3)))
        .frame(width: 18, height: 18)
        .padding(16)
        .opacity(hovering ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .help("Close (keeps running in the menu bar)")
    }

    // MARK: Builders

    private func key(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.roundKey)
            .frame(width: 36, height: 36)
            .help(help)
    }

    private func mediaKey(_ symbol: String, _ button: RemoteButton) -> some View {
        Button { model.press(button) } label: { Image(systemName: symbol).font(.system(size: 9)) }
            .buttonStyle(.pillKey(RemotePalette.keyDark))
            .frame(height: 22)
    }

    private func colorKey(_ color: Color, _ button: RemoteButton) -> some View {
        Button { model.press(button) } label: { Color.clear }
            .buttonStyle(.pillKey(color.opacity(0.85)))
            .frame(height: 12)
    }

    private func appKey(_ title: String, id: String, color: Color) -> some View {
        Button(title) { model.launch(id) }
            .buttonStyle(.pillKey(color))
            .frame(height: 28)
    }

    private func popoverKey(_ label: String, _ kind: Popover, symbol: Bool = false, help: String, size: CGFloat = 34) -> some View {
        Button {
            popover = kind
        } label: {
            if symbol { Image(systemName: label) } else { Text(label).font(.system(size: 10, weight: .bold, design: .rounded)) }
        }
        .buttonStyle(.roundKey)
        .frame(width: size, height: size)
        .help(help)
        .popover(isPresented: Binding(get: { popover == kind }, set: { if !$0 { popover = nil } }), arrowEdge: .trailing) {
            switch kind {
            case .numbers: NumberPad()
            case .apps: AppGrid { popover = nil }
            case .keyboard: TextEntry()
            case .touchpad: Touchpad()
            }
        }
    }

    // MARK: Keyboard

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow: model.press(.up)
        case .downArrow: model.press(.down)
        case .leftArrow: model.press(.left)
        case .rightArrow: model.press(.right)
        case .return, .space: model.press(.enter)
        case .delete, .escape: model.press(.back)
        default:
            switch press.characters.lowercased() {
            case "h": model.press(.home)
            case "m": model.toggleMute()
            case "=", "+": model.volumeUp()
            case "-", "_": model.volumeDown()
            case "]": model.channelUp()
            case "[": model.channelDown()
            case "p": model.press(.play)
            case "k": model.press(.pause)
            case let c where c.count == 1 && c.first!.isNumber:
                if let b = RemoteButton.named(c) { model.press(b) }
            default: return .ignored
            }
        }
        return .handled
    }
}
