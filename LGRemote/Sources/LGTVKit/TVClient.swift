import Foundation

public typealias JSON = [String: Any]

public enum TVError: LocalizedError {
    case noHost
    case notConnected
    case timeout
    case pairingRejected(String)
    case requestFailed(String)
    case badResponse
    case invalidArgument(String)

    public var errorDescription: String? {
        switch self {
        case .noHost: "No TV address configured. Run `lgremote discover` or set one in Settings."
        case .notConnected: "Not connected to the TV."
        case .timeout: "The TV did not respond in time."
        case .pairingRejected(let m): "Pairing failed: \(m)"
        case .requestFailed(let m): m
        case .badResponse: "Unexpected response from the TV."
        case .invalidArgument(let m): m
        }
    }
}

/// A single connection to an LG webOS TV over its SSAP WebSocket API (wss, port 3001).
/// Clients are one-shot: once disconnected, create a new one to reconnect.
public final class TVClient: NSObject, URLSessionDelegate, @unchecked Sendable {
    public let host: String
    public private(set) var clientKey: String?
    public var onPairingPrompt: (@Sendable () -> Void)?
    public var onDisconnect: (@Sendable (Error?) -> Void)?

    private var session: URLSession!
    private let lock = NSLock()
    private var socket: URLSessionWebSocketTask?
    private var pointer: URLSessionWebSocketTask?
    private var registered = false
    private var closedByUser = false
    private var nextID = 0
    private var pending: [String: CheckedContinuation<JSON, Error>] = [:]
    private var subscriptions: [String: @Sendable (JSON) -> Void] = [:]
    private var registration: CheckedContinuation<String, Error>?

    public init(host: String, clientKey: String? = nil) {
        self.host = host
        self.clientKey = clientKey
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    public var isConnected: Bool { lock.withLock { registered } }

    // MARK: Connection

    /// Connects and registers. Shows a pairing prompt on the TV if there is no valid client key.
    /// Returns the client key, which should be persisted.
    @discardableResult
    public func connect(pairingTimeout: TimeInterval = 60) async throws -> String {
        guard !host.isEmpty, let url = URL(string: "wss://\(host):3001") else { throw TVError.noHost }
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 8 << 20
        lock.withLock { socket = task }
        task.resume()
        receive(on: task)

        var payload: JSON = ["forcePairing": false, "pairingType": "PROMPT", "manifest": Manifest.value]
        if let clientKey { payload["client-key"] = clientKey }

        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in
            lock.withLock { registration = c }
            send(["id": "register", "type": "register", "payload": payload], on: task)
            DispatchQueue.global().asyncAfter(deadline: .now() + pairingTimeout) { [weak self] in
                self?.finishRegistration(.failure(TVError.timeout))
            }
        }
    }

    public func disconnect() {
        let task = lock.withLock { () -> URLSessionWebSocketTask? in
            closedByUser = true
            return socket
        }
        task?.cancel(with: .goingAway, reason: nil)
        if task == nil { session.invalidateAndCancel() }
    }

    // MARK: Requests

    public func request(_ uri: String, _ payload: JSON = [:], timeout: TimeInterval = 10) async throws -> JSON {
        guard let task = lock.withLock({ registered ? socket : nil }) else { throw TVError.notConnected }
        let id = makeID("req")
        return try await withCheckedThrowingContinuation { c in
            lock.withLock { pending[id] = c }
            send(["id": id, "type": "request", "uri": uri, "payload": payload], on: task)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.resolve(id, .failure(TVError.timeout))
            }
        }
    }

    /// Subscribes to a URI. The handler is called with the initial value and every change,
    /// on a background queue.
    public func subscribe(_ uri: String, _ payload: JSON = [:], handler: @escaping @Sendable (JSON) -> Void) throws {
        guard let task = lock.withLock({ registered ? socket : nil }) else { throw TVError.notConnected }
        let id = makeID("sub")
        lock.withLock { subscriptions[id] = handler }
        send(["id": id, "type": "subscribe", "uri": uri, "payload": payload], on: task)
    }

    // MARK: Pointer / buttons

    public func button(_ name: String) async throws {
        try await sendPointer("type:button\nname:\(name)\n\n")
    }

    public func move(dx: Double, dy: Double, drag: Bool = false) async throws {
        try await sendPointer("type:move\ndx:\(dx)\ndy:\(dy)\ndown:\(drag ? 1 : 0)\n\n")
    }

    public func click() async throws {
        try await sendPointer("type:click\n\n")
    }

    public func scroll(dx: Double, dy: Double) async throws {
        try await sendPointer("type:scroll\ndx:\(dx)\ndy:\(dy)\n\n")
    }

    private func sendPointer(_ message: String) async throws {
        let p = try await pointerSocket()
        do {
            try await p.send(.string(message))
        } catch {
            lock.withLock { if pointer === p { pointer = nil } }
            throw error
        }
    }

    private func pointerSocket() async throws -> URLSessionWebSocketTask {
        if let p = lock.withLock({ pointer }) { return p }
        let res = try await request("ssap://com.webos.service.networkinput/getPointerInputSocket")
        guard let path = res["socketPath"] as? String, let url = URL(string: path) else { throw TVError.badResponse }
        let task = session.webSocketTask(with: url)
        task.resume()
        lock.withLock { pointer = task }
        pointerReceive(task)
        return task
    }

    private func pointerReceive(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            if case .failure = result {
                self.lock.withLock { if self.pointer === task { self.pointer = nil } }
            } else {
                self.pointerReceive(task)
            }
        }
    }

    // MARK: Plumbing

    private func makeID(_ prefix: String) -> String {
        lock.withLock {
            nextID += 1
            return "\(prefix)_\(nextID)"
        }
    }

    private func send(_ message: JSON, on task: URLSessionWebSocketTask) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        let id = message["id"] as? String ?? ""
        task.send(.string(text)) { [weak self] error in
            guard let error else { return }
            if id == "register" { self?.finishRegistration(.failure(error)) } else { self?.resolve(id, .failure(error)) }
        }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let s): self.handle(s)
                case .data(let d): self.handle(String(decoding: d, as: UTF8.self))
                @unknown default: break
                }
                self.receive(on: task)
            case .failure(let error):
                self.connectionClosed(task, error)
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let msg = (try? JSONSerialization.jsonObject(with: data)) as? JSON else { return }
        let id = msg["id"] as? String ?? ""
        let type = msg["type"] as? String ?? ""
        let payload = msg["payload"] as? JSON ?? [:]

        if id == "register" {
            switch type {
            case "registered":
                let key = payload["client-key"] as? String ?? ""
                lock.withLock {
                    clientKey = key
                    registered = true
                }
                finishRegistration(.success(key))
            case "response":
                if payload["pairingType"] as? String == "PROMPT" { onPairingPrompt?() }
            case "error":
                finishRegistration(.failure(TVError.pairingRejected(msg["error"] as? String ?? "rejected")))
            default:
                break
            }
            return
        }

        if let handler = lock.withLock({ subscriptions[id] }) {
            if type != "error" { handler(payload) }
            return
        }

        if type == "error" {
            resolve(id, .failure(TVError.requestFailed(msg["error"] as? String ?? "Request failed")))
        } else if payload["returnValue"] as? Bool == false {
            let text = payload["errorText"] as? String ?? payload["errorMessage"] as? String ?? "Request failed"
            resolve(id, .failure(TVError.requestFailed(text)))
        } else {
            resolve(id, .success(payload))
        }
    }

    private func resolve(_ id: String, _ result: Result<JSON, Error>) {
        guard let c = lock.withLock({ pending.removeValue(forKey: id) }) else { return }
        c.resume(with: result)
    }

    private func finishRegistration(_ result: Result<String, Error>) {
        guard let c = lock.withLock({ () -> CheckedContinuation<String, Error>? in
            defer { registration = nil }
            return registration
        }) else { return }
        c.resume(with: result)
    }

    private func connectionClosed(_ task: URLSessionWebSocketTask, _ error: Error) {
        let state = lock.withLock { () -> ([CheckedContinuation<JSON, Error>], CheckedContinuation<String, Error>?, Bool)? in
            guard socket === task else { return nil }
            let conts = Array(pending.values)
            let reg = registration
            pending.removeAll()
            subscriptions.removeAll()
            registration = nil
            socket = nil
            pointer = nil
            registered = false
            return (conts, reg, closedByUser)
        }
        guard let (conts, reg, byUser) = state else { return }
        session.invalidateAndCancel()
        conts.forEach { $0.resume(throwing: error) }
        reg?.resume(throwing: error)
        if !byUser { onDisconnect?(error) }
    }

    // The TV uses a self-signed certificate; trust it only for this TV's host.
    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           challenge.protectionSpace.host == host,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
