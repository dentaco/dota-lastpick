// Renders the app icon (1024, opaque) and the header mark (transparent) from the web favicon's diamond motif.
//   swift tools/make_icon.swift <icon.png> <mark.png>
import AppKit

func render(_ px: Int, opaque: Bool, to path: String) {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let cs = CGColorSpaceCreateDeviceRGB()
    func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a).cgColor }
    let gold = c(217, 168, 78), red = c(229, 72, 77)

    if opaque {
        ctx.setFillColor(c(11, 10, 13)); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        // ember glow from the top right, faint green from bottom left
        let g1 = CGGradient(colorsSpace: cs, colors: [c(229, 72, 77, 0.42), c(229, 72, 77, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g1, startCenter: CGPoint(x: s * 0.78, y: s * 0.86), startRadius: 0, endCenter: CGPoint(x: s * 0.78, y: s * 0.86), endRadius: s * 0.75, options: [])
        let g2 = CGGradient(colorsSpace: cs, colors: [c(95, 211, 138, 0.16), c(95, 211, 138, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g2, startCenter: CGPoint(x: s * 0.1, y: s * 0.05), startRadius: 0, endCenter: CGPoint(x: s * 0.1, y: s * 0.05), endRadius: s * 0.6, options: [])
        // embers
        var seed: UInt64 = 42
        func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
        for i in 0..<46 {
            let r = 3 + rnd() * 7
            ctx.setFillColor([red, gold, c(255, 122, 61)][i % 3].copy(alpha: 0.25 + rnd() * 0.5)!)
            ctx.fillEllipse(in: CGRect(x: rnd() * s, y: rnd() * s, width: r, height: r))
        }
    }
    let cx = s / 2, cy = s / 2
    let outer = s * (opaque ? 0.33 : 0.44), inner = s * (opaque ? 0.135 : 0.18)
    func diamond(_ r: CGFloat, _ squash: CGFloat = 0.84) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: cx, y: cy + r)); p.addLine(to: CGPoint(x: cx + r * squash, y: cy))
        p.addLine(to: CGPoint(x: cx, y: cy - r)); p.addLine(to: CGPoint(x: cx - r * squash, y: cy)); p.closeSubpath()
        return p
    }
    ctx.setShadow(offset: .zero, blur: s * 0.05, color: c(217, 168, 78, opaque ? 0.55 : 0))
    ctx.addPath(diamond(outer)); ctx.setStrokeColor(gold); ctx.setLineWidth(s * (opaque ? 0.045 : 0.075)); ctx.setLineJoin(.miter); ctx.strokePath()
    ctx.setShadow(offset: .zero, blur: s * 0.06, color: c(229, 72, 77, opaque ? 0.8 : 0))
    let rg = CGGradient(colorsSpace: cs, colors: [c(255, 110, 90), red] as CFArray, locations: [0, 1])!
    ctx.saveGState(); ctx.addPath(diamond(inner, 1)); ctx.clip()
    ctx.drawLinearGradient(rg, start: CGPoint(x: cx, y: cy + inner), end: CGPoint(x: cx, y: cy - inner), options: [])
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    var png = rep.representation(using: .png, properties: [:])!
    if opaque { // strip alpha: App Store icons must be opaque
        let flat = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        flat.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: s, height: s))
        png = NSBitmapImageRep(cgImage: flat.makeImage()!).representation(using: .png, properties: [:])!
    }
    try! png.write(to: URL(fileURLWithPath: path))
}
render(1024, opaque: true, to: CommandLine.arguments[1])
render(120, opaque: false, to: CommandLine.arguments[2])
