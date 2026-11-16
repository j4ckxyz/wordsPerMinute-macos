import AppKit
import Foundation
import Testing

/// Guards against the 0.1.0 bug: a misspelled/nonexistent SF Symbol renders as an
/// empty image, which left the menu bar item blank. Scans the app sources for
/// symbol names and checks every one exists on this OS.
@Suite("SF Symbols")
struct SymbolTests {
    static let appSources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/WPMBar")

    static func symbolNames() throws -> Set<String> {
        let files = try FileManager.default.contentsOfDirectory(at: appSources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let marker = try NSRegularExpression(pattern: #"systemName|systemImage|symbolName|bullet\("#)
        let literal = try NSRegularExpression(pattern: #""([a-z][a-z0-9]*(?:\.[a-z0-9]+)*)""#)
        var names = Set<String>()
        for file in files {
            for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map(String.init) {
                let range = NSRange(line.startIndex..., in: line)
                guard marker.firstMatch(in: line, range: range) != nil else { continue }
                for m in literal.matches(in: line, range: range) {
                    names.insert(String(line[Range(m.range(at: 1), in: line)!]))
                }
            }
        }
        return names
    }

    @Test func everySymbolUsedByTheAppExists() throws {
        let names = try Self.symbolNames()
        #expect(names.count >= 10, "scanner found too few symbols: \(names)")
        #expect(names.contains("gauge.with.dots.needle.67percent"))
        for name in names.sorted() {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "missing SF Symbol: \(name)")
        }
    }

    @Test func theOld010SymbolReallyIsMissing() {
        // Documents the root cause of the blank menu bar item in 0.1.0.
        #expect(NSImage(systemSymbolName: "keyboard.badge.exclamationmark", accessibilityDescription: nil) == nil)
    }
}
