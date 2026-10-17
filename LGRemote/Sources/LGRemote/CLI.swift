import AppKit
import Foundation
import LGTVKit

enum CLI {
    static let usage = """
    lgremote — control your LG webOS TV

    USAGE: lgremote <command> [arguments]

    Setup
      discover                 Find LG TVs on the network (saves one if none is configured)
      pair                     Pair with the TV (accept the prompt on the TV)
      config                   Show configuration
      config host <ip>         Set the TV's IP address
      config mac <mac>         Set the TV's MAC address (needed for power on)
      config forget            Forget the pairing key

    Power
      on                       Turn on via Wake-on-LAN
      off                      Turn off
      screen on|off            Turn the screen on/off (audio keeps playing)

    Volume & channels
      vol                      Show volume
      vol up|down|<0-100>|+N|-N
      mute [on|off|toggle]
      ch [up|down]             Show or change channel

    Navigation
      up down left right ok back home menu exit info
      play pause stop rewind ff red green yellow blue 0-9
      key <name>...            Send several buttons in sequence
      move <dx> <dy> | click | scroll <dy>    Pointer control

    Apps & inputs
      apps                     List installed apps
      app <name|id>            Launch an app (fuzzy match on name)
      close <name|id>          Close an app
      inputs                   List inputs
      input <name|id>          Switch input (e.g. "input hdmi 2")
      url <url>                Open a URL in the TV browser

    Other
      status                   Volume, current app and system info
      watch                    Stream volume and app changes until Ctrl-C
      text <string> [--enter]  Type into the focused text field
      toast <message>          Show a notification on the TV
      info                     System information
      raw <ssap-uri> [json]    Send any SSAP request
      gui                      Open the remote window
      help                     Show this help
    """

    static func run(_ args: [String]) async -> Int32 {
        do {
            try await execute(args)
            return 0
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    private static func execute(_ arguments: [String]) async throws {
        var args = arguments
        let command = args.removeFirst().lowercased()
        var config = TVConfig.load()

        switch command {
        case "help", "-h", "--help":
            print(usage)
        case "version", "--version":
            print("lgremote 1.0")
        case "discover":
            try discover(&config)
        case "config":
            try configure(args, &config)
        case "on", "wake":
            try wake(config)
        case "power" where args.first == "on":
            try wake(config)
        case "gui", "open":
            openGUI()
        default:
            let tv = try await connect(&config)
            defer { tv.disconnect() }
            try await perform(command, args, tv)
        }
    }

    // MARK: Commands that need a connection

    private static func perform(_ command: String, _ args: [String], _ tv: TVClient) async throws {
        let rest = args.joined(separator: " ")
        switch command {
        case "pair":
            print("Paired with \(tv.host).")
        case "status":
            let vol = try await tv.volume()
            let appID = try await tv.foregroundAppID()
            let title = try? await tv.apps().first { $0.id == appID }?.title
            let info = try await tv.systemInfo()
            print("TV:      \(info["modelName"] as? String ?? "?") at \(tv.host)")
            print("App:     \(title ?? appID ?? "?")")
            print("Volume:  \(vol.volume)\(vol.muted ? " (muted)" : "")")
        case "off", "power":
            try await tv.powerOff()
        case "screen":
            switch args.first {
            case "off": try await tv.screenOff()
            case "on": try await tv.screenOn()
            default: throw TVError.invalidArgument("usage: lgremote screen on|off")
            }
        case "vol", "volume":
            try await volume(args.first, tv)
        case "mute":
            let target: Bool
            switch args.first {
            case "on": target = true
            case "off": target = false
            default: target = !(try await tv.volume().muted)
            }
            try await tv.setMute(target)
            print(target ? "Muted" : "Unmuted")
        case "ch", "channel":
            switch args.first {
            case "up", "+": try await tv.channelUp()
            case "down", "-": try await tv.channelDown()
            default:
                let ch = try await tv.currentChannel()
                print("\(ch["channelNumber"] as? String ?? "?")  \(ch["channelName"] as? String ?? "")")
            }
        case "key", "press":
            guard !args.isEmpty else { throw TVError.invalidArgument("usage: lgremote key <name>...") }
            for name in args {
                guard let button = RemoteButton.named(name) else { throw TVError.invalidArgument("Unknown button: \(name)") }
                try await tv.button(button.rawValue)
                try await Task.sleep(for: .milliseconds(150))
            }
        case "apps":
            for app in try await tv.apps() { print("\(app.id.padding(toLength: 36, withPad: " ", startingAt: 0)) \(app.title)") }
        case "app", "launch":
            let app = try await findApp(rest, tv)
            try await tv.launch(app.id)
            print("Launched \(app.title)")
        case "close":
            let app = try await findApp(rest, tv)
            try await tv.closeApp(app.id)
        case "inputs":
            for input in try await tv.inputs() {
                print("\(input.id.padding(toLength: 14, withPad: " ", startingAt: 0)) \(input.label)\(input.connected ? "  (connected)" : "")")
            }
        case "input":
            let inputs = try await tv.inputs()
            let query = rest.lowercased().replacingOccurrences(of: " ", with: "")
            guard let input = inputs.first(where: {
                $0.id.lowercased().replacingOccurrences(of: "_", with: "") == query
                    || $0.label.lowercased().replacingOccurrences(of: " ", with: "") == query
            }) else { throw TVError.invalidArgument("No input matching \"\(rest)\". Try `lgremote inputs`.") }
            try await tv.switchInput(input.id)
        case "url", "browse":
            try await tv.openURL(rest)
        case "text", "type":
            let enter = args.contains("--enter")
            try await tv.insertText(args.filter { $0 != "--enter" }.joined(separator: " "))
            if enter { try await tv.sendEnter() }
        case "toast", "notify":
            try await tv.toast(rest)
        case "info":
            printJSON(try await tv.systemInfo())
        case "raw":
            guard let uri = args.first else { throw TVError.invalidArgument("usage: lgremote raw <ssap-uri> [json]") }
            var payload: JSON = [:]
            if args.count > 1 {
                guard let parsed = try? JSONSerialization.jsonObject(with: Data(args.dropFirst().joined(separator: " ").utf8)) as? JSON
                else { throw TVError.invalidArgument("Payload must be a JSON object") }
                payload = parsed
            }
            printJSON(try await tv.request(uri, payload))
        case "move":
            guard args.count == 2, let dx = Double(args[0]), let dy = Double(args[1]) else {
                throw TVError.invalidArgument("usage: lgremote move <dx> <dy>")
            }
            try await tv.move(dx: dx, dy: dy)
        case "click":
            try await tv.click()
        case "scroll":
            try await tv.scroll(dx: 0, dy: Double(args.first ?? "") ?? 1)
        case "watch":
            try await watch(tv)
        default:
            guard let button = RemoteButton.named(command) else {
                throw TVError.invalidArgument("Unknown command \"\(command)\". Run `lgremote help`.")
            }
            try await tv.button(button.rawValue)
        }
    }

    private static func volume(_ arg: String?, _ tv: TVClient) async throws {
        switch arg {
        case nil:
            let v = try await tv.volume()
            print("\(v.volume)\(v.muted ? " (muted)" : "")")
            return
        case "up", "+": try await tv.volumeUp()
        case "down", "-": try await tv.volumeDown()
        case let s? where s.hasPrefix("+") || s.hasPrefix("-"):
            guard let delta = Int(s) else { throw TVError.invalidArgument("Invalid volume: \(s)") }
            try await tv.setVolume(try await tv.volume().volume + delta)
        case let s?:
            guard let level = Int(s) else { throw TVError.invalidArgument("Invalid volume: \(s)") }
            try await tv.setVolume(level)
        }
        print("Volume: \(try await tv.volume().volume)")
    }

    private static func findApp(_ query: String, _ tv: TVClient) async throws -> TVApp {
        guard !query.isEmpty else { throw TVError.invalidArgument("Specify an app name or id. Try `lgremote apps`.") }
        let apps = try await tv.apps()
        let q = query.lowercased()
        if let app = apps.first(where: { $0.id.lowercased() == q || $0.title.lowercased() == q })
            ?? apps.first(where: { $0.title.lowercased().hasPrefix(q) })
            ?? apps.first(where: { $0.title.lowercased().contains(q) || $0.id.lowercased().contains(q) }) {
            return app
        }
        // Unknown to the launcher list, but may still be a valid app id.
        return TVApp(id: query, title: query)
    }

    private static func watch(_ tv: TVClient) async throws {
        let apps = (try? await tv.apps()) ?? []
        try tv.subscribe("ssap://audio/getVolume") { json in
            if let v = VolumeState(json: json) { print("volume \(v.volume)\(v.muted ? " muted" : "")") }
        }
        try tv.subscribe("ssap://com.webos.applicationManager/getForegroundAppInfo") { json in
            let id = json["appId"] as? String ?? ""
            print("app    \(apps.first { $0.id == id }?.title ?? id)")
        }
        print("Watching \(tv.host) — press Ctrl-C to stop.")
        while tv.isConnected { try await Task.sleep(for: .seconds(1)) }
        throw TVError.requestFailed("Connection to the TV closed.")
    }

    // MARK: Commands that don't need a connection

    private static func connect(_ config: inout TVConfig) async throws -> TVClient {
        guard let host = config.host, !host.isEmpty else { throw TVError.noHost }
        let tv = TVClient(host: host, clientKey: config.clientKey)
        tv.onPairingPrompt = {
            FileHandle.standardError.write(Data("Accept the pairing prompt on your TV…\n".utf8))
        }
        let key = try await tv.connect()
        if key != config.clientKey {
            config.clientKey = key
            try config.save()
        }
        return tv
    }

    private static func discover(_ config: inout TVConfig) throws {
        print("Searching for LG TVs…")
        let found = Discovery.search()
        guard !found.isEmpty else {
            print("None found. Make sure the TV is on and on the same network.")
            return
        }
        for tv in found { print("  \(tv.host)  \(tv.name ?? "LG TV")  \(tv.mac ?? "")") }
        if config.host == nil || found.count == 1, let tv = found.first {
            if config.host != tv.host { config.clientKey = nil }
            config.host = tv.host
            config.name = tv.name
            if let mac = tv.mac { config.mac = mac }
            try config.save()
            print("Saved \(tv.host) as your TV.")
        }
    }

    private static func configure(_ args: [String], _ config: inout TVConfig) throws {
        switch (args.first, args.dropFirst().first) {
        case (nil, _):
            print("Host:    \(config.host ?? "—")")
            print("MAC:     \(config.mac ?? "—")")
            print("Name:    \(config.name ?? "—")")
            print("Paired:  \(config.clientKey == nil ? "no" : "yes")")
            print("File:    \(TVConfig.fileURL.path)")
            return
        case ("host", let value?):
            if config.host != value { config.clientKey = nil }
            config.host = value
        case ("mac", let value?):
            config.mac = value.uppercased()
        case ("forget", _):
            config.clientKey = nil
        default:
            throw TVError.invalidArgument("usage: lgremote config [host <ip> | mac <mac> | forget]")
        }
        try config.save()
        print("Saved.")
    }

    private static func wake(_ config: TVConfig) throws {
        guard let mac = config.mac else {
            throw TVError.invalidArgument("No MAC address configured. Run `lgremote config mac <mac>`.")
        }
        try WakeOnLAN.send(mac: mac, host: config.host)
        print("Wake-on-LAN packet sent to \(mac).")
        print("If the TV doesn't turn on, enable Settings › General › Devices › TV Management › \"Turn on via Wi-Fi\".")
    }

    private static func openGUI() {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundle = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        if bundle.pathExtension == "app" {
            NSWorkspace.shared.open(bundle)
        } else {
            let p = Process()
            p.executableURL = exe
            try? p.run()
        }
    }

    private static func printJSON(_ json: JSON) {
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            print(String(decoding: data, as: UTF8.self))
        }
    }
}
