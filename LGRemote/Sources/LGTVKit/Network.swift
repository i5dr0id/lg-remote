import Foundation

public struct DiscoveredTV: Sendable, Hashable {
    public let host: String
    public let name: String?
    public let mac: String?
}

/// Finds LG TVs on the local network with an SSDP M-SEARCH.
public enum Discovery {
    public static func search(timeout: TimeInterval = 3) -> [DiscoveredTV] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { Darwin.close(fd) }

        var tv = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let query = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\n"
            + "ST: urn:lge-com:service:webos-second-screen:1\r\n\r\n"
        var dest = makeAddress("239.255.255.250", port: 1900)
        for _ in 0..<2 {
            _ = withUnsafePointer(to: &dest) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, query, query.utf8.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        var found: [String: DiscoveredTV] = [:]
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var from = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, buffer.count, 0, $0, &len) }
            }
            guard n > 0 else { continue }
            var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &from.sin_addr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
            let ip = String(decoding: ipBuf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard found[ip] == nil else { continue }
            let text = String(decoding: buffer[0..<n], as: UTF8.self)
            found[ip] = DiscoveredTV(host: ip, name: header("DLNADeviceName.lge.com", in: text), mac: macAddress(for: ip))
        }
        return found.values.sorted { $0.host < $1.host }
    }

    /// Looks up a host's MAC address in the system ARP table.
    public static func macAddress(for ip: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-an"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard let line = out.split(separator: "\n").first(where: { $0.contains("(\(ip))") }),
              let range = line.range(of: " at ") else { return nil }
        let raw = line[range.upperBound...].prefix { !$0.isWhitespace }
        let parts = raw.split(separator: ":")
        guard parts.count == 6 else { return nil }
        return parts.map { $0.count == 1 ? "0\($0)" : String($0) }.joined(separator: ":").uppercased()
    }

    private static func header(_ name: String, in response: String) -> String? {
        for line in response.split(whereSeparator: \.isNewline) {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame {
                let value = pair[1].trimmingCharacters(in: .whitespaces)
                return value.removingPercentEncoding ?? value
            }
        }
        return nil
    }
}

/// Wakes the TV with a magic packet. The TV must have "Turn on via Wi-Fi" / "Mobile TV On" enabled.
public enum WakeOnLAN {
    public static func send(mac: String, host: String? = nil) throws {
        let bytes = mac.split(whereSeparator: { $0 == ":" || $0 == "-" }).compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6 else { throw TVError.invalidArgument("Invalid MAC address: \(mac)") }
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet += bytes }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw TVError.requestFailed("Could not open UDP socket") }
        defer { Darwin.close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))

        var targets = ["255.255.255.255"]
        if let host, let subnet = subnetBroadcast(for: host) { targets.append(subnet) }
        for target in targets {
            for port: UInt16 in [9, 7] {
                var addr = makeAddress(target, port: port)
                _ = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
    }

    /// Assumes a /24 network, which covers typical home routers.
    static func subnetBroadcast(for host: String) -> String? {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return parts.prefix(3).joined(separator: ".") + ".255"
    }
}

private func makeAddress(_ ip: String, port: UInt16) -> sockaddr_in {
    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    inet_pton(AF_INET, ip, &addr.sin_addr)
    return addr
}
