import Foundation

/// Persists daily counts as JSON in Application Support. Counts only.
public struct StatsStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("WPMBar", isDirectory: true).appendingPathComponent("days.json")
    }

    private struct File: Codable {
        var version = 1
        var days: [DayStats]
    }

    public func load() -> [DayStats] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode(File.self, from: data).days
        } catch {
            // Keep the unreadable file aside rather than overwriting it.
            let stamp = Int(Date().timeIntervalSince1970)
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("corrupt-\(stamp)"))
            return []
        }
    }

    public func save(_ days: [DayStats]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(File(days: days)).write(to: url, options: .atomic)
    }
}
