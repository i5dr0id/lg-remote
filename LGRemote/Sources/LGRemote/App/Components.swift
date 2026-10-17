import LGTVKit
import SwiftUI

enum RemotePalette {
    static let bodyTop = Color(white: 0.17)
    static let bodyBottom = Color(white: 0.07)
    static let key = Color(white: 0.25)
    static let keyDark = Color(white: 0.19)
    static let label = Color.white.opacity(0.92)
    static let secondaryLabel = Color.white.opacity(0.45)
    static let power = Color(red: 0.86, green: 0.16, blue: 0.2)
    static let display = Color(red: 0.05, green: 0.09, blue: 0.08)
    static let displayText = Color(red: 0.55, green: 0.95, blue: 0.75)
}

/// A physical-looking remote key: raised, glossy, sinks when pressed.
struct KeyStyle<S: Shape>: ButtonStyle {
    var shape: S
    var fill: Color = RemotePalette.key
    var foreground: Color = RemotePalette.label
    var fontSize: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                shape.fill(fill.gradient.shadow(.inner(color: .white.opacity(0.14), radius: 0.5, y: 1)))
            )
            .overlay(shape.stroke(.black.opacity(0.55), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.55), radius: configuration.isPressed ? 0.5 : 2.5, y: configuration.isPressed ? 0.5 : 2)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .contentShape(shape)
    }
}

extension ButtonStyle where Self == KeyStyle<Circle> {
    static var roundKey: KeyStyle<Circle> { KeyStyle(shape: Circle()) }
    static func roundKey(_ fill: Color, fontSize: CGFloat = 13) -> KeyStyle<Circle> {
        KeyStyle(shape: Circle(), fill: fill, fontSize: fontSize)
    }
}

extension ButtonStyle where Self == KeyStyle<Capsule> {
    static var pillKey: KeyStyle<Capsule> { KeyStyle(shape: Capsule(), fontSize: 11) }
    static func pillKey(_ fill: Color, foreground: Color = RemotePalette.label) -> KeyStyle<Capsule> {
        KeyStyle(shape: Capsule(), fill: fill, foreground: foreground, fontSize: 11)
    }
}

/// Flat key used inside rockers and the D-pad ring: only the glyph reacts.
struct GlyphKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(RemotePalette.label.opacity(configuration.isPressed ? 0.5 : 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(configuration.isPressed ? 0.08 : 0.001))
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct DPad: View {
    @Environment(TVModel.self) private var model
    var diameter: CGFloat = 168

    var body: some View {
        let arrow = diameter * 0.3
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.27), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
                    .shadow(.inner(color: .white.opacity(0.12), radius: 1, y: 1)))
                .overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 4, y: 3)

            VStack(spacing: 0) {
                arrowKey("chevron.up", .up).frame(width: arrow, height: arrow)
                Spacer()
                arrowKey("chevron.down", .down).frame(width: arrow, height: arrow)
            }
            HStack(spacing: 0) {
                arrowKey("chevron.left", .left).frame(width: arrow, height: arrow)
                Spacer()
                arrowKey("chevron.right", .right).frame(width: arrow, height: arrow)
            }

            Button("OK") { model.press(.enter) }
                .buttonStyle(.roundKey(Color(white: 0.3), fontSize: diameter * 0.09))
                .frame(width: diameter * 0.42, height: diameter * 0.42)
        }
        .frame(width: diameter, height: diameter)
    }

    private func arrowKey(_ symbol: String, _ button: RemoteButton) -> some View {
        Button { model.press(button) } label: { Image(systemName: symbol) }
            .buttonStyle(GlyphKeyStyle())
            .clipShape(Circle())
    }
}

struct Rocker: View {
    let title: String
    let upSymbol: String
    let downSymbol: String
    let up: () -> Void
    let down: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: up) { Image(systemName: upSymbol) }.buttonStyle(GlyphKeyStyle())
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(RemotePalette.secondaryLabel)
            Button(action: down) { Image(systemName: downSymbol) }.buttonStyle(GlyphKeyStyle())
        }
        .clipShape(Capsule())
        .background(
            Capsule().fill(LinearGradient(colors: [Color(white: 0.26), Color(white: 0.17)], startPoint: .top, endPoint: .bottom)
                .shadow(.inner(color: .white.opacity(0.12), radius: 0.5, y: 1)))
        )
        .overlay(Capsule().stroke(.black.opacity(0.55), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.55), radius: 2.5, y: 2)
    }
}

struct StatusLight: View {
    @Environment(TVModel.self) private var model

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.9), radius: 3)
            .help(model.statusText)
    }

    private var color: Color {
        switch model.status {
        case .connected: .green
        case .connecting, .pairing: .orange
        case .idle, .failed: Color(white: 0.4)
        }
    }
}

/// The little LCD strip at the top of the remote.
struct RemoteDisplay: View {
    @Environment(TVModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Text(model.flashMessage ?? model.statusText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if model.isConnected, let volume = model.volume {
                Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 9))
                Text("\(volume)").monospacedDigit()
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(RemotePalette.displayText)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7).fill(RemotePalette.display.shadow(.inner(color: .black, radius: 2))))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.06)))
    }
}

struct NumberPad: View {
    @Environment(TVModel.self) private var model
    private let keys: [[(String, RemoteButton)]] = [
        [("1", .num1), ("2", .num2), ("3", .num3)],
        [("4", .num4), ("5", .num5), ("6", .num6)],
        [("7", .num7), ("8", .num8), ("9", .num9)],
        [("–", .dash), ("0", .num0), ("List", .list)],
    ]

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(keys.indices, id: \.self) { row in
                GridRow {
                    ForEach(keys[row], id: \.0) { key in
                        Button(key.0) { model.press(key.1) }
                            .buttonStyle(.pillKey)
                            .frame(width: 54, height: 28)
                    }
                }
            }
        }
        .padding(16)
        .background(RemotePalette.bodyBottom)
    }
}

struct AppGrid: View {
    @Environment(TVModel.self) private var model
    var onLaunch: () -> Void = {}

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(model.apps) { app in
                    Button(app.title) {
                        model.launch(app.id)
                        onLaunch()
                    }
                    .buttonStyle(.pillKey(app.id == model.foregroundAppID ? Color(white: 0.38) : RemotePalette.key))
                    .lineLimit(1)
                    .frame(height: 28)
                }
            }
            .padding(14)
        }
        .frame(width: 280, height: 340)
        .background(RemotePalette.bodyBottom)
        .overlay {
            if model.apps.isEmpty {
                Text(model.isConnected ? "Loading apps…" : "Not connected")
                    .foregroundStyle(RemotePalette.secondaryLabel)
            }
        }
        .task { if model.apps.isEmpty { await model.refreshLists() } }
    }
}

struct TextEntry: View {
    @Environment(TVModel.self) private var model
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Type on TV")
                .font(.headline)
            TextField("Text to send", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
            HStack {
                Button("Send", action: send).keyboardShortcut(.defaultAction)
                Button("Enter ⏎") { model.sendEnter() }
                Button("⌫") { model.deleteCharacter() }
            }
            Text("Focus a text field on the TV first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 260)
    }

    private func send() {
        guard !text.isEmpty else { return }
        model.sendText(text)
        text = ""
    }
}

/// Drag to move the TV's pointer; click to select.
struct Touchpad: View {
    @Environment(TVModel.self) private var model
    @State private var last: CGPoint?

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(white: 0.12).shadow(.inner(color: .black, radius: 3)))
            .overlay(Text("Drag to move · click to select").font(.caption2).foregroundStyle(RemotePalette.secondaryLabel))
            .frame(width: 240, height: 160)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if let last {
                            let dx = value.location.x - last.x, dy = value.location.y - last.y
                            if abs(dx) + abs(dy) >= 2 {
                                model.movePointer(dx: dx * 1.6, dy: dy * 1.6)
                                self.last = value.location
                            }
                        } else {
                            last = value.location
                        }
                    }
                    .onEnded { value in
                        if abs(value.translation.width) + abs(value.translation.height) < 3 { model.click() }
                        last = nil
                    }
            )
            .padding(14)
            .background(RemotePalette.bodyBottom)
    }
}
