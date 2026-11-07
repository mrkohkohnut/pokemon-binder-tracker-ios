import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Renders the Poké Binder app icon: fanned trading cards behind a glossy Poké Ball.
// Usage: swift MakeIcon.swift <output-dir>

let S: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.displayP3)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }
func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    rgb(CGFloat((v >> 16) & 0xff) / 255, CGFloat((v >> 8) & 0xff) / 255, CGFloat(v & 0xff) / 255, a)
}

enum Variant { case light, dark, tinted }

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint, locations: [CGFloat]? = nil) {
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ ctx: CGContext, _ colors: [CGColor], center: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

func card(_ ctx: CGContext, center: CGPoint, angle: CGFloat, variant: Variant, art: [CGColor]) {
    let w: CGFloat = 360, h: CGFloat = 504, r: CGFloat = 30
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle * .pi / 180)
    let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)

    // Shadow
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: rgb(0, 0, 0, 0.30))
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.setFillColor(variant == .tinted ? hex(0xD9D9D9) : hex(0xFFD43B))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Yellow border sheen
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.clip()
    if variant != .tinted {
        linear(ctx, [hex(0xFFE57A), hex(0xF5B800)], from: CGPoint(x: 0, y: h / 2), to: CGPoint(x: 0, y: -h / 2))
    }
    ctx.restoreGState()

    // Art window
    let inset: CGFloat = 26
    let art1 = CGRect(x: rect.minX + inset, y: rect.midY - 10, width: w - inset * 2, height: h / 2 - inset + 10 - 4)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: art1, cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.clip()
    linear(ctx, art, from: CGPoint(x: 0, y: art1.maxY), to: CGPoint(x: 0, y: art1.minY))
    ctx.restoreGState()

    // Text lines
    ctx.setFillColor(variant == .tinted ? rgb(0.55, 0.55, 0.55, 0.6) : rgb(0.45, 0.32, 0, 0.35))
    for (i, frac) in [0.78, 0.62, 0.70].enumerated() {
        let y = rect.midY - 60 - CGFloat(i) * 46
        let lw = (w - inset * 2) * frac
        ctx.addPath(CGPath(roundedRect: CGRect(x: rect.minX + inset, y: y, width: lw, height: 20), cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.fillPath()
    }
    ctx.restoreGState()
}

func pokeBall(_ ctx: CGContext, center c: CGPoint, diameter d: CGFloat, variant: Variant) {
    let r = d / 2
    let circle = CGRect(x: c.x - r, y: c.y - r, width: d, height: d)
    let ink = variant == .tinted ? hex(0x1A1A1A) : hex(0x1C1E26)

    // Drop shadow + ink outline disc
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 50, color: rgb(0, 0, 0, 0.38))
    ctx.setFillColor(ink)
    ctx.fillEllipse(in: circle)
    ctx.restoreGState()

    let outline = d * 0.045
    let inner = circle.insetBy(dx: outline, dy: outline)

    // Top half
    ctx.saveGState()
    ctx.addEllipse(in: inner); ctx.clip()
    ctx.clip(to: CGRect(x: inner.minX, y: c.y, width: inner.width, height: inner.height / 2))
    switch variant {
    case .tinted: linear(ctx, [hex(0x9A9A9A), hex(0x6E6E6E)], from: CGPoint(x: c.x, y: inner.maxY), to: CGPoint(x: c.x, y: c.y))
    default: linear(ctx, [hex(0xFF6B6B), hex(0xF0303A), hex(0xC8102E)], from: CGPoint(x: inner.minX, y: inner.maxY), to: CGPoint(x: inner.maxX, y: c.y))
    }
    ctx.restoreGState()

    // Bottom half
    ctx.saveGState()
    ctx.addEllipse(in: inner); ctx.clip()
    ctx.clip(to: CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: inner.height / 2))
    linear(ctx, [hex(0xFFFFFF), hex(0xE6E9EF), hex(0xC9CED8)], from: CGPoint(x: c.x, y: c.y), to: CGPoint(x: c.x, y: inner.minY))
    ctx.restoreGState()

    // Band
    let band = d * 0.085
    ctx.setFillColor(ink)
    ctx.fill(CGRect(x: inner.minX, y: c.y - band / 2, width: inner.width, height: band))

    // Button
    let b1 = d * 0.36, b2 = d * 0.25, b3 = d * 0.17
    ctx.fillEllipse(in: CGRect(x: c.x - b1 / 2, y: c.y - b1 / 2, width: b1, height: b1))
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - b2 / 2, y: c.y - b2 / 2, width: b2, height: b2)); ctx.clip()
    linear(ctx, [hex(0xFFFFFF), hex(0xD5DAE2)], from: CGPoint(x: c.x, y: c.y + b2 / 2), to: CGPoint(x: c.x, y: c.y - b2 / 2))
    ctx.restoreGState()
    ctx.setStrokeColor(rgb(0, 0, 0, 0.10)); ctx.setLineWidth(3)
    ctx.strokeEllipse(in: CGRect(x: c.x - b3 / 2, y: c.y - b3 / 2, width: b3, height: b3))

    // Specular highlight on top half
    ctx.saveGState()
    ctx.addEllipse(in: inner); ctx.clip()
    ctx.translateBy(x: c.x - r * 0.38, y: c.y + r * 0.55)
    ctx.rotate(by: 28 * .pi / 180)
    ctx.scaleBy(x: 1, y: 0.42)
    radial(ctx, [rgb(1, 1, 1, 0.55), rgb(1, 1, 1, 0)], center: .zero, radius: r * 0.42)
    ctx.restoreGState()
}

func render(_ variant: Variant) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Background (iOS masks the squircle itself).
    switch variant {
    case .light:
        linear(ctx, [hex(0xFF5F5F), hex(0xE8263A), hex(0xB5122B)], from: CGPoint(x: 0, y: S), to: CGPoint(x: S * 0.4, y: 0))
        radial(ctx, [rgb(1, 1, 1, 0.22), rgb(1, 1, 1, 0)], center: CGPoint(x: S * 0.3, y: S * 0.85), radius: S * 0.6)
    case .dark:
        linear(ctx, [hex(0x2C2D35), hex(0x15161B)], from: CGPoint(x: 0, y: S), to: CGPoint(x: 0, y: 0))
        radial(ctx, [rgb(0.95, 0.2, 0.25, 0.30), rgb(0.95, 0.2, 0.25, 0)], center: CGPoint(x: S * 0.5, y: S * 0.55), radius: S * 0.55)
    case .tinted:
        ctx.setFillColor(hex(0x000000)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    }

    let blueArt = variant == .tinted ? [hex(0xBDBDBD), hex(0x8A8A8A)] : [hex(0x9BE3FF), hex(0x3D8BFF)]
    let greenArt = variant == .tinted ? [hex(0xC8C8C8), hex(0x9A9A9A)] : [hex(0xC6F7A0), hex(0x3FBF6B)]
    card(ctx, center: CGPoint(x: 400, y: 600), angle: 13, variant: variant, art: greenArt)
    card(ctx, center: CGPoint(x: 624, y: 600), angle: -13, variant: variant, art: blueArt)
    pokeBall(ctx, center: CGPoint(x: 512, y: 372), diameter: 470, variant: variant)
    return ctx.makeImage()!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
for (variant, name) in [(Variant.light, "AppIcon.png"), (.dark, "AppIcon-Dark.png"), (.tinted, "AppIcon-Tinted.png")] {
    var image = render(variant)
    if variant == .tinted {
        // Tinted icons must be grayscale.
        let gray = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        gray.draw(image, in: CGRect(x: 0, y: 0, width: S, height: S))
        image = gray.makeImage()!
    } else {
        // Opaque, no alpha channel (App Store requirement).
        let flat = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        flat.draw(image, in: CGRect(x: 0, y: 0, width: S, height: S))
        image = flat.makeImage()!
    }
    let dest = CGImageDestinationCreateWithURL(out.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote", name)
}
