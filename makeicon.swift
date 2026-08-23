import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let s = size
    let ctx = NSGraphicsContext.current!.cgContext

    // 圓角底：深色漸層，讓亮綠折線跳出來
    let r = NSRect(x: 0, y: 0, width: s, height: s)
    let radius = s * 0.2237                       // macOS 圖示的標準圓角比例
    let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
    path.addClip()
    let grad = NSGradient(colors: [
        NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.18, alpha: 1),
        NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1),
    ])!
    grad.draw(in: r, angle: -90)

    // 折線圖：一路往右上，代表行情
    let pts: [(CGFloat, CGFloat)] = [
        (0.18, 0.34), (0.34, 0.50), (0.46, 0.40), (0.62, 0.62), (0.82, 0.72),
    ]
    let line = NSBezierPath()
    line.lineWidth = s * 0.075
    line.lineCapStyle = .round
    line.lineJoinStyle = .round
    line.move(to: NSPoint(x: pts[0].0 * s, y: pts[0].1 * s))
    for p in pts.dropFirst() { line.line(to: NSPoint(x: p.0 * s, y: p.1 * s)) }

    ctx.setShadow(offset: .zero, blur: s * 0.06,
                  color: NSColor(calibratedRed: 0.18, green: 0.90, blue: 0.44, alpha: 0.7).cgColor)
    NSColor(calibratedRed: 0.18, green: 0.90, blue: 0.44, alpha: 1).setStroke()
    line.stroke()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // 末端的圓點：強調「即時」
    let dot = s * 0.075
    let last = pts.last!
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: last.0 * s - dot, y: last.1 * s - dot,
                                width: dot * 2, height: dot * 2)).fill()

    img.unlockFocus()
    return img
}

let iconset = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for (px, name) in [(16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),
                   (128,"128x128"),(256,"128x128@2x"),(256,"256x256"),
                   (512,"256x256@2x"),(512,"512x512"),(1024,"512x512@2x")] {
    let img = drawIcon(size: CGFloat(px))
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(iconset)/icon_\(name).png"))
}
print("icons written")
