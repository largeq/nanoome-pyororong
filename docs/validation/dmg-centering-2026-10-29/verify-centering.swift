import AppKit
import CryptoKit

// Read the original 2x Finder JPEGs; never redraw or save either image.
func measure(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let bitmap = NSBitmapImageRep(data: data), let bytes = bitmap.bitmapData,
          !bitmap.isPlanar, bitmap.bitsPerSample == 8, bitmap.samplesPerPixel == 3,
          bitmap.bitmapFormat.rawValue == 0, bitmap.pixelsWide == 1536 else {
        fatalError("Expected the original 1536px-wide RGB Finder screenshot")
    }
    // Decoded JPEGs may use 32 bits/pixel despite reporting three color samples.
    let stride = bitmap.bitsPerPixel / 8
    func minimumRGB(_ x: Int, _ y: Int) -> Int {
        let i = y * bitmap.bytesPerRow + x * stride
        return min(Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }
    var longest = 0..<0, start = 0
    for y in 0...bitmap.pixelsHigh {
        let white = y < bitmap.pixelsHigh
            && (1200..<1300).filter { minimumRGB($0, y) >= 250 }.count >= 98
        if white { continue }
        if y - start > longest.count { longest = start..<y }
        start = y + 1
    }
    func foreground(_ threshold: Int) -> [String: Int] {
        let rows = longest.filter { y in
            (200..<1300).filter { minimumRGB($0, y) <= threshold }.count >= 3
        }
        guard let top = rows.first, let bottom = rows.last else { fatalError("No content pixels") }
        let upper = top - longest.lowerBound
        let lower = longest.upperBound - 1 - bottom
        return ["top": top, "bottomInclusive": bottom, "topMarginPixels": upper,
                "bottomMarginPixels": lower, "marginDifferencePixels": upper - lower]
    }
    return ["source": path, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            "imagePixels": [bitmap.pixelsWide, bitmap.pixelsHigh],
            "bodyYInclusive": [longest.lowerBound, longest.upperBound - 1],
            "foregroundRGB160": foreground(160), "antialiasingDiagnosticRGB200": foreground(200)]
}

guard CommandLine.arguments.count == 4 else {
    fatalError("Usage: swift verify-centering.swift <original-r2.jpg> <actual-r4.jpg> <centering.json>")
}
let baseline = try measure(CommandLine.arguments[1])
let actual = try measure(CommandLine.arguments[2])
let before = baseline["foregroundRGB160"] as! [String: Int]
let after = actual["foregroundRGB160"] as! [String: Int]
let checks: [String: Bool] = [
    "bothOriginalWindowSizes1536x960": baseline["imagePixels"] as! [Int] == [1536, 960]
        && actual["imagePixels"] as! [Int] == [1536, 960],
    "sameBody120Through902Inclusive": baseline["bodyYInclusive"] as! [Int] == [120, 902]
        && actual["bodyYInclusive"] as! [Int] == [120, 902],
    "bothMarginsExactly214Pixels": after["topMarginPixels"] == 214 && after["bottomMarginPixels"] == 214,
    "zeroMarginDifference": after["marginDifferencePixels"] == 0,
    "bothContentEdgesMovedUp98Pixels": before["top"]! - after["top"]! == 98
        && before["bottomInclusive"]! - after["bottomInclusive"]! == 98
]
let passed = checks.values.allSatisfy { $0 }
let report: [String: Any] = [
    "status": passed ? "passed" : "failed", "measuredAtUTC": ISO8601DateFormatter().string(from: Date()),
    "coordinateOrigin": "top-left; top sharing control and title/tab area confirm y increases downward",
    "pixelScale": 2, "whiteColumnXHalfOpen": [1200, 1300], "contentXHalfOpen": [200, 1300],
    "bodyRule": "Longest run of rows with at least 98/100 column pixels having every RGB channel >= 250",
    "foregroundRule": "At least 3 content-region pixels in a row with minimum RGB channel <= 160",
    "acceptanceRule": "Both actual margins equal exactly 214 pixels, difference 0; both edges moved up exactly 98 pixels from r2",
    "antialiasingRule": "RGB <= 200 is diagnostic only and never affects the RGB <= 160 acceptance result",
    "baselineR2": baseline, "actualR4": actual, "checks": checks,
    "upwardShiftPixels": 98, "upwardShiftPoints": 49,
    "actualTopMarginPoints": Double(after["topMarginPixels"]!) / 2,
    "actualBottomMarginPoints": Double(after["bottomMarginPixels"]!) / 2,
    "imagesModified": false
]
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
print("Centering \(passed ? "passed" : "failed"): top \(after["topMarginPixels"]!)px; bottom \(after["bottomMarginPixels"]!)px; difference \(after["marginDifferencePixels"]!)px")
if !passed { exit(1) }
