// Renders the app mark into an .iconset without actool: the Icon Composer file is macOS 26 only.
import AppKit

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <mark.svg> <out.iconset>\n".utf8))
    exit(1)
}

let markURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let mark = NSImage(contentsOf: markURL) else {
    FileHandle.standardError.write(Data("cannot read \(markURL.path)\n".utf8))
    exit(1)
}

/// A continuous-corner square, the shape an app icon has on macOS.
func squircle(in rect: CGRect) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.height * 0.22)
}

func render(_ size: Int) -> Data? {
    let points = CGFloat(size)
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let rect = CGRect(x: 0, y: 0, width: points, height: points)
    squircle(in: rect).addClip()
    NSGradient(
        colors: [
            NSColor(srgbRed: 0.05, green: 0.09, blue: 0.18, alpha: 1),
            NSColor(srgbRed: 0.04, green: 0.42, blue: 1, alpha: 1),
        ]
    )?.draw(in: rect, angle: -90)

    let glyphWidth = points * 0.46
    let glyphHeight = glyphWidth * mark.size.height / mark.size.width
    let glyph = CGRect(
        x: (points - glyphWidth) / 2, y: (points - glyphHeight) / 2,
        width: glyphWidth, height: glyphHeight)
    // The mark is a black path; a transparency layer lets it be repainted white without
    // touching the gradient already drawn underneath.
    let cg = context.cgContext
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    mark.draw(in: glyph, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
              hints: nil)
    NSColor.white.setFill()
    glyph.fill(using: .sourceAtop)
    cg.endTransparencyLayer()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

try? FileManager.default.removeItem(at: outURL)
try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

for (name, size) in variants {
    guard let data = render(size) else {
        FileHandle.standardError.write(Data("cannot render \(name)\n".utf8))
        exit(1)
    }
    try data.write(to: outURL.appendingPathComponent(name + ".png"))
}
