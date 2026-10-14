// Draws the disk image window's background (640×400 pt, @1x and @2x):
//   swift scripts/dmg/make-background.swift scripts/dmg
// then: tiffutil -cathidpicheck background.png background@2x.png -out background.tiff
//
// Finder draws the icon labels black in light mode and white in dark mode, so the area under the
// icons is a mid indigo where both stay readable (about 4.5:1).
import AppKit

let folder = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let size = NSSize(width: 640, height: 400)

func render(scale: CGFloat, to path: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Indigo, lighter at the top, like the app icon and the website.
    NSGradient(colors: [
        NSColor(srgbRed: 0.53, green: 0.49, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.43, green: 0.39, blue: 0.91, alpha: 1),
        NSColor(srgbRed: 0.36, green: 0.31, blue: 0.86, alpha: 1),
    ])!.draw(in: NSRect(origin: .zero, size: size), angle: -90)

    let center = NSMutableParagraphStyle()
    center.alignment = .center
    let title: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: center,
    ]
    let subtitle: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14, weight: .regular),
        .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        .paragraphStyle: center,
    ]
    NSAttributedString(string: "Drag Mixpilot into Applications", attributes: title)
        .draw(in: NSRect(x: 0, y: 318, width: size.width, height: 32))
    NSAttributedString(string: "Zieh Mixpilot in den Ordner „Programme“.", attributes: subtitle)
        .draw(in: NSRect(x: 0, y: 296, width: size.width, height: 22))

    // The arrow between the two icons (centers at x 170 and 470, y 200 from the top).
    let arrow = NSBezierPath()
    arrow.lineWidth = 5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    let y = size.height - 196
    arrow.move(to: NSPoint(x: 268, y: y))
    arrow.line(to: NSPoint(x: 372, y: y))
    arrow.move(to: NSPoint(x: 352, y: y + 18))
    arrow.line(to: NSPoint(x: 374, y: y))
    arrow.line(to: NSPoint(x: 352, y: y - 18))
    NSColor.white.withAlphaComponent(0.9).setStroke()
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

render(scale: 1, to: "\(folder)/background.png")
render(scale: 2, to: "\(folder)/background@2x.png")
