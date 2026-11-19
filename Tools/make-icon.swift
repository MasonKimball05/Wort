// Draws Wort's icon: a white "W" on red, with two dots above it like an umlaut.
// Run: swift Tools/make-icon.swift   (writes Resources/Assets.xcassets/AppIcon.appiconset)
import AppKit

let out = URL(fileURLWithPath: "Resources/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let red = NSColor(srgbRed: 0.85, green: 0.19, blue: 0.17, alpha: 1)
    let dark = NSColor(srgbRed: 0.62, green: 0.10, blue: 0.10, alpha: 1)
    NSGradient(starting: red, ending: dark)!.draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: -90)
    let font = NSFont.systemFont(ofSize: s * 0.58, weight: .heavy)
    let w = NSAttributedString(string: "W", attributes: [.font: font, .foregroundColor: NSColor.white])
    let size = w.size()
    w.draw(at: NSPoint(x: (s - size.width) / 2, y: s * 0.12))
    NSColor.white.setFill()
    let d = s * 0.11
    for x in [s * 0.36, s * 0.64] {
        NSBezierPath(ovalIn: NSRect(x: x - d / 2, y: s * 0.72, width: d, height: d)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = [["filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]]
try render(1024).write(to: out.appendingPathComponent("icon-1024.png"))
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "mac-\(pt)@\(scale)x.png"
    try render(pt * scale).write(to: out.appendingPathComponent(name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(pt)x\(pt)"])
}
let json = try JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]],
                                      options: [.prettyPrinted, .sortedKeys])
try json.write(to: out.appendingPathComponent("Contents.json"))
print("wrote \(images.count) icons")
