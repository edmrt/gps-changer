import Foundation
import CoreLocation

// Apple's own tool for this: `xcrun devicectl device simulate location …` (the same location simulation Xcode does).
// The iPhone has to be paired with this Mac (USB or the same Wi-Fi) with Developer Mode on.
struct Device: Identifiable, Hashable, Sendable {
    let id: String          // CoreDevice identifier, what devicectl's --device takes
    let name: String
    let model: String       // "iPhone", "iPad"
    let os: String
    let connected: Bool
    let developerMode: Bool
}

enum DeviceCtl {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // Physical iPhones and iPads this Mac knows.
    static func devices() async throws -> [Device] {
        let json = try await run(["list", "devices"])
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let list = (root["result"] as? [String: Any])?["devices"] as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            let hw = d["hardwareProperties"] as? [String: Any] ?? [:]
            let props = d["deviceProperties"] as? [String: Any] ?? [:]
            let conn = d["connectionProperties"] as? [String: Any] ?? [:]
            guard hw["reality"] as? String == "physical", hw["platform"] as? String == "iOS",
                  let id = d["identifier"] as? String else { return nil }
            let type = hw["deviceType"] as? String ?? "iPhone"
            return Device(
                id: id,
                name: props["name"] as? String ?? type,
                model: type.lowercased().contains("ipad") ? "iPad" : "iPhone",
                os: props["osVersionNumber"] as? String ?? "",
                connected: conn["tunnelState"] as? String == "connected",
                developerMode: props["developerModeStatus"] as? String == "enabled"
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func setLocation(_ c: CLLocationCoordinate2D, on device: Device) async throws {
        // "--name=value": a separate "-79.38" would be read as an option.
        _ = try await run(["device", "simulate", "location", "coordinate", "--device", device.id,
                           "--latitude=" + String(format: "%.6f", c.latitude), "--longitude=" + String(format: "%.6f", c.longitude)])
    }

    // Back to the phone's real GPS.
    static func clear(on device: Device) async throws {
        _ = try await run(["device", "simulate", "location", "clear", "--device", device.id])
    }

    // Runs devicectl with its JSON written to a temporary file; on failure, devicectl's own error message.
    private static func run(_ args: [String]) async throws -> Data {
        try await Task.detached {
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("devicectl-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: out) }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            p.arguments = ["devicectl"] + args + ["--timeout", "60", "--json-output", out.path]
            let errPipe = Pipe()
            p.standardError = errPipe
            p.standardOutput = errPipe
            try p.run()
            let text = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            let json = (try? Data(contentsOf: out)) ?? Data()
            let ok = p.terminationStatus == 0
            log("devicectl \(args.joined(separator: " ")) → \(ok ? "ok" : "exit \(p.terminationStatus): \(message(json: json, text: text))")")
            guard ok else { throw Failure(message: message(json: json, text: text)) }
            return json
        }.value
    }

    // ~/Library/Logs/GPS Changer.log: every devicectl run and how it ended.
    static func log(_ line: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/GPS Changer.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("\(stamp) \(line)\n".utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    private static func message(json: Data, text: String) -> String {
        if let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
           let error = (root["error"] as? [String: Any]) ?? ((root["info"] as? [String: Any])?["error"] as? [String: Any]),
           let info = error["userInfo"] as? [String: Any] {
            let text = (info["NSLocalizedDescription"] as? [String: Any])?["string"] as? String
            let reason = (info["NSLocalizedFailureReason"] as? [String: Any])?["string"] as? String
                ?? (info["NSLocalizedRecoverySuggestion"] as? [String: Any])?["string"] as? String
            if let text { return [text, reason].compactMap { $0 }.joined(separator: " ") }
        }
        let lines = text.split(separator: "\n").map(String.init).filter { $0.localizedCaseInsensitiveContains("error") || $0.hasPrefix("ERROR") }
        return lines.last ?? (text.isEmpty ? "devicectl failed." : String(text.suffix(300)))
    }
}
