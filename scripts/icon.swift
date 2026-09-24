// icon.swift — the Geist mark, rendered by AppKit at every size macOS
// wants, so the app icon and the menu bar glyph come from one geometry.
//
//   swift scripts/icon.swift <out-dir>
//   → <out-dir>/AppIcon.icns, MenuBarIcon.png (18 pt), MenuBarIcon@2x.png
//
// The mark: a thin ring holding five rounded bars that swell towards the
// middle — a breath, a waveform, a model speaking. Dark ink ground, warm
// paper-white mark. Nothing else.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icon"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

let ink   = NSColor(srgbRed: 0.106, green: 0.114, blue: 0.145, alpha: 1) // #1b1d25
let inkLo = NSColor(srgbRed: 0.055, green: 0.059, blue: 0.078, alpha: 1) // #0e0f14
let paper = NSColor(srgbRed: 0.965, green: 0.953, blue: 0.925, alpha: 1) // #f6f3ec

/// Draw the mark centred in `rect`, scaled to it. `stroke` is the ring's
/// line width as a fraction of the rect's side.
func drawMark(in rect: NSRect, color: NSColor) {
    let s = min(rect.width, rect.height)
    let c = NSPoint(x: rect.midX, y: rect.midY)
    let ringR = 0.34 * s
    let ringW = 0.042 * s
    let ring = NSBezierPath(ovalIn: NSRect(x: c.x - ringR, y: c.y - ringR, width: 2 * ringR, height: 2 * ringR))
    ring.lineWidth = ringW
    color.setStroke()
    ring.stroke()

    let heights: [CGFloat] = [0.14, 0.26, 0.38, 0.26, 0.14]
    let barW = 0.058 * s
    let gap  = 0.052 * s
    let total = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
    var x = c.x - total / 2
    color.setFill()
    for h in heights {
        let bh = h * s
        let bar = NSBezierPath(roundedRect: NSRect(x: x, y: c.y - bh / 2, width: barW, height: bh),
                               xRadius: barW / 2, yRadius: barW / 2)
        bar.fill()
        x += barW + gap
    }
}

/// macOS app icon: the standard rounded square (radius ≈ 22.37 % of the
/// side) on a transparent canvas with the ~10 % margin Apple's grid uses.
func appIcon(px: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    let s = CGFloat(px)
    let inset = 0.10 * s
    let square = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: square, xRadius: 0.2237 * square.width, yRadius: 0.2237 * square.width)
    NSGradient(starting: ink, ending: inkLo)!.draw(in: shape, angle: -90)
    // a hairline of light along the top edge, as glass does
    shape.addClip()
    NSColor.white.withAlphaComponent(0.06).setStroke()
    let hair = NSBezierPath(roundedRect: square.insetBy(dx: 0.004 * s, dy: 0.004 * s),
                            xRadius: 0.2237 * square.width, yRadius: 0.2237 * square.width)
    hair.lineWidth = 0.008 * s
    hair.stroke()
    drawMark(in: square.insetBy(dx: 0.14 * square.width, dy: 0.14 * square.width), color: paper)
    img.unlockFocus()
    return img
}

/// Menu bar template glyph: the mark alone, black on transparent; macOS
/// tints it for light/dark menu bars.
func menuGlyph(pt: Int, scale: Int) -> NSImage {
    let px = pt * scale
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    drawMark(in: NSRect(x: 0, y: 0, width: px, height: px).insetBy(dx: CGFloat(px) * 0.04, dy: CGFloat(px) * 0.04),
             color: .black)
    img.unlockFocus()
    return img
}

func png(_ img: NSImage, _ path: String) {
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let set = out + "/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: set)
try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    png(appIcon(px: px), "\(set)/icon_\(name).png")
}
png(appIcon(px: 1024), out + "/AppIcon-1024.png") // for READMEs and a quick look
png(menuGlyph(pt: 18, scale: 1), out + "/MenuBarIcon.png")
png(menuGlyph(pt: 18, scale: 2), out + "/MenuBarIcon@2x.png")

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", set, "-o", out + "/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "icon: \(out)/AppIcon.icns, MenuBarIcon@{1,2}x.png" : "icon: iconutil failed")
exit(iconutil.terminationStatus)
