import CoreGraphics
import Foundation

func number(_ value: Any?) -> Double {
    switch value {
    case let value as Double:
        return value
    case let value as CGFloat:
        return Double(value)
    case let value as Int:
        return Double(value)
    case let value as NSNumber:
        return value.doubleValue
    default:
        return 0
    }
}

let listAll = CommandLine.arguments.contains("--list")
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var mainID: Int?
for window in windows {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    guard owner == "Prometh" else { continue }
    let layer = Int(number(window[kCGWindowLayer as String]))
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let width = number(bounds["Width"])
    let height = number(bounds["Height"])
    let identifier = Int(number(window[kCGWindowNumber as String]))
    if listAll {
        print("\(identifier) layer=\(layer) \(Int(width))x\(Int(height))")
    }
    if layer == 0, height > 100 {
        mainID = identifier
    }
}
if listAll {
    exit(mainID == nil ? 1 : 0)
}
if let mainID {
    print(mainID)
    exit(0)
}
exit(1)
