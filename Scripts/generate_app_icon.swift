import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
let sizes = [16, 32, 64, 128, 256, 512, 1024]

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

for size in sizes {
    let dimension = CGFloat(size)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Unable to create bitmap for icon size \(size)")
    }

    bitmap.size = NSSize(width: dimension, height: dimension)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    NSColor(calibratedRed: 0.02, green: 0.19, blue: 0.40, alpha: 1).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: 0, y: 0, width: dimension, height: dimension),
        xRadius: dimension * 0.22,
        yRadius: dimension * 0.22
    ).fill()

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: dimension * 0.34, weight: .heavy),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraphStyle,
    ]
    NSString(string: "MB").draw(
        in: NSRect(x: 0, y: dimension * 0.32, width: dimension, height: dimension * 0.36),
        withAttributes: attributes
    )

    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Unable to render icon size \(size)")
    }

    try pngData.write(to: outputDirectory.appendingPathComponent("AppIcon-\(size).png"))
}
