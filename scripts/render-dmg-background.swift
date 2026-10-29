import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("사용법: swift scripts/render-dmg-background.swift <출력 폴더>\n", stderr)
    exit(64)
}

// Finder draws the two real file icons over this background at the positions in dmg-settings.py.
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let canvas = NSSize(width: 768, height: 480)
let instruction = "표로롱을 응용 프로그램 폴더로 드래그하세요."
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15),
    .foregroundColor: NSColor(srgbRed: 0.36, green: 0.36, blue: 0.36, alpha: 1),
    .paragraphStyle: paragraph,
]
guard let arrow = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)?
    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [
            NSColor(srgbRed: 0.53, green: 0.53, blue: 0.53, alpha: 1),
        ]))) else {
    fatalError("설치 안내 화살표를 만들 수 없습니다.")
}

for scale in [1, 2] {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas.width) * scale,
        pixelsHigh: Int(canvas.height) * scale, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("설치 안내 배경을 만들 수 없습니다.")
    }
    bitmap.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    NSColor.white.setFill()
    NSRect(origin: .zero, size: canvas).fill()
    (instruction as NSString).draw(in: NSRect(x: 0, y: 360, width: 768, height: 24),
                                  withAttributes: attributes)
    arrow.draw(in: NSRect(x: 365, y: 259, width: 38, height: 36))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("설치 안내 배경을 PNG로 저장할 수 없습니다.")
    }
    let name = scale == 1 ? "background.png" : "background@2x.png"
    try png.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
}
