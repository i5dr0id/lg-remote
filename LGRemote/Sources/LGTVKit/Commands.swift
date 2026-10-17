import Foundation

public struct TVApp: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct TVInput: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let connected: Bool
}

public struct VolumeState: Sendable, Equatable {
    public let volume: Int
    public let muted: Bool

    public init?(json: JSON) {
        let status = json["volumeStatus"] as? JSON ?? json
        guard let volume = status["volume"] as? Int else { return nil }
        self.volume = volume
        self.muted = status["muteStatus"] as? Bool ?? status["muted"] as? Bool ?? false
    }
}

public enum RemoteButton: String, CaseIterable, Sendable {
    case up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT", enter = "ENTER"
    case back = "BACK", home = "HOME", menu = "MENU", exit = "EXIT", info = "INFO", list = "LIST"
    case guide = "GUIDE", qmenu = "QMENU"
    case red = "RED", green = "GREEN", yellow = "YELLOW", blue = "BLUE"
    case volumeUp = "VOLUMEUP", volumeDown = "VOLUMEDOWN", mute = "MUTE"
    case channelUp = "CHANNELUP", channelDown = "CHANNELDOWN"
    case play = "PLAY", pause = "PAUSE", stop = "STOP", rewind = "REWIND", fastForward = "FASTFORWARD"
    case num0 = "0", num1 = "1", num2 = "2", num3 = "3", num4 = "4"
    case num5 = "5", num6 = "6", num7 = "7", num8 = "8", num9 = "9", dash = "DASH"

    private static let aliases: [String: RemoteButton] = [
        "ok": .enter, "select": .enter, "settings": .menu, "ff": .fastForward, "forward": .fastForward,
        "rw": .rewind, "volup": .volumeUp, "voldown": .volumeDown, "chup": .channelUp, "chdown": .channelDown,
        "-": .dash,
    ]

    /// Resolves a user-typed name like "ok", "up", "HOME", "volumeup" or "5".
    public static func named(_ name: String) -> RemoteButton? {
        let lower = name.lowercased()
        if let alias = aliases[lower] { return alias }
        return RemoteButton(rawValue: name.uppercased())
    }
}

extension TVClient {
    // Audio
    public func volume() async throws -> VolumeState {
        guard let v = VolumeState(json: try await request("ssap://audio/getVolume")) else { throw TVError.badResponse }
        return v
    }
    public func volumeUp() async throws { _ = try await request("ssap://audio/volumeUp") }
    public func volumeDown() async throws { _ = try await request("ssap://audio/volumeDown") }
    public func setVolume(_ level: Int) async throws {
        _ = try await request("ssap://audio/setVolume", ["volume": max(0, min(100, level))])
    }
    public func setMute(_ muted: Bool) async throws { _ = try await request("ssap://audio/setMute", ["mute": muted]) }

    // Power
    public func powerOff() async throws { _ = try await request("ssap://system/turnOff") }
    public func screenOff() async throws { _ = try await request("ssap://com.webos.service.tvpower/power/turnOffScreen") }
    public func screenOn() async throws { _ = try await request("ssap://com.webos.service.tvpower/power/turnOnScreen") }

    // Channels
    public func channelUp() async throws { _ = try await request("ssap://tv/channelUp") }
    public func channelDown() async throws { _ = try await request("ssap://tv/channelDown") }
    public func currentChannel() async throws -> JSON { try await request("ssap://tv/getCurrentChannel") }

    // Apps
    public func foregroundAppID() async throws -> String? {
        try await request("ssap://com.webos.applicationManager/getForegroundAppInfo")["appId"] as? String
    }
    public func apps() async throws -> [TVApp] {
        let res = try await request("ssap://com.webos.applicationManager/listLaunchPoints")
        let points = res["launchPoints"] as? [JSON] ?? []
        return points.compactMap { p in
            guard let id = p["id"] as? String else { return nil }
            return TVApp(id: id, title: p["title"] as? String ?? id)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
    public func launch(_ appID: String, params: JSON? = nil) async throws {
        var payload: JSON = ["id": appID]
        if let params { payload["params"] = params }
        _ = try await request("ssap://system.launcher/launch", payload)
    }
    public func closeApp(_ appID: String) async throws { _ = try await request("ssap://system.launcher/close", ["id": appID]) }
    public func openURL(_ url: String) async throws { _ = try await request("ssap://system.launcher/open", ["target": url]) }

    // Inputs
    public func inputs() async throws -> [TVInput] {
        let res = try await request("ssap://tv/getExternalInputList")
        let devices = res["devices"] as? [JSON] ?? []
        return devices.compactMap { d in
            guard let id = d["id"] as? String else { return nil }
            return TVInput(id: id, label: d["label"] as? String ?? id, connected: d["connected"] as? Bool ?? false)
        }
    }
    public func switchInput(_ inputID: String) async throws { _ = try await request("ssap://tv/switchInput", ["inputId": inputID]) }

    // Text & notifications
    public func toast(_ message: String) async throws {
        _ = try await request("ssap://system.notifications/createToast", ["message": message])
    }
    public func insertText(_ text: String, replace: Bool = false) async throws {
        _ = try await request("ssap://com.webos.service.ime/insertText", ["text": text, "replace": replace ? 1 : 0])
    }
    public func deleteCharacters(_ count: Int) async throws {
        _ = try await request("ssap://com.webos.service.ime/deleteCharacters", ["count": count])
    }
    public func sendEnter() async throws { _ = try await request("ssap://com.webos.service.ime/sendEnterKey") }

    // Info
    public func systemInfo() async throws -> JSON { try await request("ssap://system/getSystemInfo") }
}
