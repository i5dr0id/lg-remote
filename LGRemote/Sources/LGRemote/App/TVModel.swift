import Foundation
import LGTVKit
import Observation

@MainActor
@Observable
final class TVModel {
    static let shared = TVModel()

    enum Status: Equatable {
        case idle, connecting, pairing, connected
        case failed(String)
    }

    var status: Status = .idle
    var config = TVConfig.load()
    var volume: Int?
    var muted = false
    var foregroundAppID: String?
    var apps: [TVApp] = []
    var inputs: [TVInput] = []
    var discovered: [DiscoveredTV] = []
    var isDiscovering = false
    var flashMessage: String?

    @ObservationIgnored private var client: TVClient?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?

    var isConnected: Bool { status == .connected }

    var foregroundAppTitle: String? {
        guard let id = foregroundAppID, !id.isEmpty else { return nil }
        return apps.first { $0.id == id }?.title ?? id
    }

    var statusText: String {
        switch status {
        case .idle: "Not connected"
        case .connecting: "Connecting…"
        case .pairing: "Accept prompt on TV"
        case .connected: foregroundAppTitle ?? config.name ?? "Connected"
        case .failed(let message): message
        }
    }

    // MARK: Connection

    func connect() async {
        if let connectTask {
            await connectTask.value
            return
        }
        reconnectTask?.cancel()
        let task = Task { await performConnect() }
        connectTask = task
        await task.value
        connectTask = nil
    }

    func reconnect() {
        client?.disconnect()
        client = nil
        status = .idle
        Task { await connect() }
    }

    private func performConnect() async {
        guard let host = config.host, !host.isEmpty else {
            status = .failed("Set the TV address in Settings")
            return
        }
        status = .connecting
        let tv = TVClient(host: host, clientKey: config.clientKey)
        tv.onPairingPrompt = {
            Task { @MainActor in TVModel.shared.status = .pairing }
        }
        tv.onDisconnect = { [weak tv] _ in
            Task { @MainActor in
                guard let tv else { return }
                TVModel.shared.handleDisconnect(tv)
            }
        }
        client = tv
        do {
            let key = try await tv.connect()
            guard client === tv else { return }
            if key != config.clientKey {
                config.clientKey = key
                try? config.save()
            }
            status = .connected
            subscribe(tv)
            await refreshLists()
        } catch {
            guard client === tv else { return }
            client = nil
            status = .failed(Self.describe(error))
            scheduleReconnect()
        }
    }

    private func handleDisconnect(_ tv: TVClient) {
        guard client === tv else { return }
        client = nil
        status = .failed("TV disconnected")
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            await connect()
        }
    }

    private func subscribe(_ tv: TVClient) {
        try? tv.subscribe("ssap://audio/getVolume") { json in
            guard let v = VolumeState(json: json) else { return }
            Task { @MainActor in
                TVModel.shared.volume = v.volume
                TVModel.shared.muted = v.muted
            }
        }
        try? tv.subscribe("ssap://com.webos.applicationManager/getForegroundAppInfo") { json in
            let id = json["appId"] as? String
            Task { @MainActor in TVModel.shared.foregroundAppID = id }
        }
    }

    func refreshLists() async {
        guard let tv = client else { return }
        if let apps = try? await tv.apps() { self.apps = apps }
        if let inputs = try? await tv.inputs() { self.inputs = inputs }
    }

    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet:
                return "TV is off or unreachable"
            default: break
            }
        }
        return error.localizedDescription
    }

    // MARK: Actions

    func run(_ action: @escaping (TVClient) async throws -> Void) {
        Task {
            if !isConnected { await connect() }
            guard let tv = client, isConnected else {
                flash("Not connected")
                return
            }
            do { try await action(tv) } catch { flash(Self.describe(error)) }
        }
    }

    func press(_ button: RemoteButton) { run { try await $0.button(button.rawValue) } }
    func volumeUp() { run { try await $0.volumeUp() } }
    func volumeDown() { run { try await $0.volumeDown() } }
    func toggleMute() { let target = !muted; run { try await $0.setMute(target) } }
    func channelUp() { run { try await $0.channelUp() } }
    func channelDown() { run { try await $0.channelDown() } }
    func launch(_ appID: String) { run { try await $0.launch(appID) } }
    func switchInput(_ id: String) { run { try await $0.switchInput(id) } }
    func sendText(_ text: String) { run { try await $0.insertText(text) } }
    func sendEnter() { run { try await $0.sendEnter() } }
    func deleteCharacter() { run { try await $0.deleteCharacters(1) } }
    func movePointer(dx: Double, dy: Double) { run { try await $0.move(dx: dx, dy: dy) } }
    func click() { run { try await $0.click() } }

    func togglePower() {
        if isConnected {
            run { try await $0.powerOff() }
        } else {
            powerOn()
        }
    }

    func powerOn() {
        guard let mac = config.mac else {
            flash("Set the TV's MAC address in Settings")
            return
        }
        do {
            try WakeOnLAN.send(mac: mac, host: config.host)
            flash("Waking TV…")
            reconnectTask?.cancel()
            reconnectTask = Task {
                for _ in 0..<6 where !isConnected {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    await connect()
                }
            }
        } catch {
            flash(error.localizedDescription)
        }
    }

    func flash(_ message: String) {
        flashMessage = message
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            flashMessage = nil
        }
    }

    // MARK: Settings

    func updateConfig(host: String, mac: String) {
        let host = host.trimmingCharacters(in: .whitespaces)
        let mac = mac.trimmingCharacters(in: .whitespaces).uppercased()
        if host != config.host { config.clientKey = nil }
        config.host = host.isEmpty ? nil : host
        config.mac = mac.isEmpty ? nil : mac
        try? config.save()
        reconnect()
    }

    func forgetPairing() {
        config.clientKey = nil
        try? config.save()
        reconnect()
    }

    func discover() {
        isDiscovering = true
        Task {
            let results = await Task.detached { Discovery.search() }.value
            discovered = results
            isDiscovering = false
        }
    }

    func use(_ tv: DiscoveredTV) {
        config.name = tv.name
        updateConfig(host: tv.host, mac: tv.mac ?? config.mac ?? "")
    }
}
