// Prints "<windowID> <width>x<height>" for each on-screen window owned by a PID.
import CoreGraphics
let pid = Int(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerPID as String] as? Int) == pid {
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print(w[kCGWindowNumber as String]!, "\(b["Width"] ?? 0)x\(b["Height"] ?? 0)", "layer", w[kCGWindowLayer as String]!)
}
