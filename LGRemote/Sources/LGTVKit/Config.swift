import Foundation

/// Shared by the GUI and the CLI: ~/Library/Application Support/LGRemote/config.json
public struct TVConfig: Codable, Sendable, Equatable {
    public var host: String?
    public var mac: String?
    public var clientKey: String?
    public var name: String?

    public init(host: String? = nil, mac: String? = nil, clientKey: String? = nil, name: String? = nil) {
        self.host = host
        self.mac = mac
        self.clientKey = clientKey
        self.name = name
    }

    public static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "LGRemote/config.json")
    }

    public static func load() -> TVConfig {
        guard let data = try? Data(contentsOf: fileURL) else { return TVConfig() }
        return (try? JSONDecoder().decode(TVConfig.self, from: data)) ?? TVConfig()
    }

    public func save() throws {
        let url = Self.fileURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
