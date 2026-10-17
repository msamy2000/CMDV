import AppKit
import Foundation

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for (px, filename) in sizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let size = CGFloat(px)
    let inset = size * 0.08
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = size * 0.22

    // Gradient rounded-rect background
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.14, green: 0.45, blue: 0.96, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.08, green: 0.24, blue: 0.68, alpha: 1.0)
    )!
    gradient.draw(in: path, angle: -65)

    // Draw clipboard symbol
    let boardWidth = size * 0.46
    let boardHeight = size * 0.54
    let boardRect = NSRect(
        x: (size - boardWidth) / 2,
        y: (size - boardHeight) / 2 - size * 0.02,
        width: boardWidth,
        height: boardHeight
    )
    let boardPath = NSBezierPath(roundedRect: boardRect, xRadius: size * 0.06, yRadius: size * 0.06)
    NSColor.white.withAlphaComponent(0.95).setFill()
    boardPath.fill()

    // Clipboard clip at top
    let clipWidth = size * 0.24
    let clipHeight = size * 0.09
    let clipRect = NSRect(
        x: (size - clipWidth) / 2,
        y: boardRect.maxY - clipHeight * 0.45,
        width: clipWidth,
        height: clipHeight
    )
    let clipPath = NSBezierPath(roundedRect: clipRect, xRadius: size * 0.03, yRadius: size * 0.03)
    NSColor(calibratedRed: 0.78, green: 0.87, blue: 1.0, alpha: 1.0).setFill()
    clipPath.fill()

    // Three horizontal card lines inside clipboard
    NSColor(calibratedRed: 0.14, green: 0.45, blue: 0.96, alpha: 0.85).setFill()
    for i in 0..<3 {
        let lineW = boardWidth * (i == 2 ? 0.50 : 0.68)
        let lineH = size * 0.045
        let lineX = boardRect.minX + boardWidth * 0.16
        let lineY = boardRect.maxY - size * (0.16 + CGFloat(i) * 0.12)
        let linePath = NSBezierPath(
            roundedRect: NSRect(x: lineX, y: lineY, width: lineW, height: lineH),
            xRadius: lineH / 2,
            yRadius: lineH / 2
        )
        linePath.fill()
    }

    NSGraphicsContext.restoreGraphicsState()

    if let pngData = rep.representation(using: .png, properties: [:]) {
        let url = URL(fileURLWithPath: outputDir).appendingPathComponent(filename)
        try pngData.write(to: url)
    }
}
