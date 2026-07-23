// Generates the Escape Plan app icon (1024x1024 light/dark/tinted variants) with CoreGraphics.
// Motif: a warm house silhouette with an escape route flowing out the front door to safety.
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let size = CGSize(width: 1024, height: 1024)

func makeContext() -> CGContext {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    return CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                     bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func save(_ ctx: CGContext, to path: String) {
    let image = ctx.makeImage()!
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func drawBackground(_ ctx: CGContext, dark: Bool, in rect: CGRect) {
    let top = dark ? rgba(0.070, 0.130, 0.220) : rgba(0.106, 0.196, 0.318)
    let bottom = dark ? rgba(0.035, 0.075, 0.135) : rgba(0.058, 0.122, 0.208)
    let grad = CGGradient(colorsSpace: nil, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.clip(to: rect)
    ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 1024),
                           end: CGPoint(x: 512, y: 0), options: [])
    ctx.restoreGState()
}

func draw(dark: Bool, tinted: Bool, to path: String) {
    let ctx = makeContext()
    let full = CGRect(origin: .zero, size: size)

    if tinted {
        ctx.clear(full)
    } else {
        drawBackground(ctx, dark: dark, in: full)
    }

    let white = tinted ? rgba(1, 1, 1) : rgba(0.973, 0.965, 0.945)
    let ember = tinted ? rgba(1, 1, 1) : rgba(1.0, 0.478, 0.161)
    let glow  = tinted ? rgba(1, 1, 1, 0.9) : rgba(0.290, 0.870, 0.500)

    // House silhouette: rounded gable + wall outline, upper two thirds.
    let wall = CGRect(x: 262, y: 330, width: 500, height: 340)
    let wallPath = CGPath(roundedRect: wall, cornerWidth: 36, cornerHeight: 36, transform: nil)
    let roof = CGMutablePath()
    roof.move(to: CGPoint(x: 200, y: 660))
    roof.addLine(to: CGPoint(x: 512, y: 880))
    roof.addLine(to: CGPoint(x: 824, y: 660))

    ctx.setStrokeColor(white)
    ctx.setLineWidth(58)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    ctx.addPath(roof)
    ctx.strokePath()
    ctx.addPath(wallPath)
    ctx.strokePath()

    // Doorway: notch the wall's bottom edge, then restore the background there and frame
    // the opening in safe-exit green.
    let slot = CGRect(x: 424, y: 290, width: 176, height: 160)
    ctx.setBlendMode(.clear)
    ctx.fill(slot)
    ctx.setBlendMode(.normal)
    if !tinted { drawBackground(ctx, dark: dark, in: slot) }

    let doorway = CGMutablePath()
    doorway.move(to: CGPoint(x: 452, y: 302))
    doorway.addLine(to: CGPoint(x: 452, y: 420))
    doorway.addArc(tangent1End: CGPoint(x: 452, y: 470), tangent2End: CGPoint(x: 512, y: 470), radius: 44)
    doorway.addArc(tangent1End: CGPoint(x: 572, y: 470), tangent2End: CGPoint(x: 572, y: 420), radius: 44)
    doorway.addLine(to: CGPoint(x: 572, y: 302))
    ctx.setStrokeColor(glow)
    ctx.setLineWidth(34)
    ctx.addPath(doorway)
    ctx.strokePath()

    // Escape route: bold ember curve flowing out of the doorway toward the bottom right.
    let route = CGMutablePath()
    route.move(to: CGPoint(x: 512, y: 405))
    route.addCurve(to: CGPoint(x: 470, y: 190),
                   control1: CGPoint(x: 512, y: 320),
                   control2: CGPoint(x: 396, y: 252))
    route.addCurve(to: CGPoint(x: 730, y: 205),
                   control1: CGPoint(x: 542, y: 130),
                   control2: CGPoint(x: 660, y: 158))
    ctx.setStrokeColor(ember)
    ctx.setLineWidth(62)
    ctx.setLineCap(.round)
    ctx.addPath(route)
    ctx.strokePath()

    // Filled arrowhead continuing the route's exit direction (up-right).
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 712, y: 118))
    arrow.addLine(to: CGPoint(x: 876, y: 262))
    arrow.addLine(to: CGPoint(x: 660, y: 300))
    arrow.closeSubpath()
    ctx.setFillColor(ember)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(40)
    ctx.setStrokeColor(ember)
    ctx.addPath(arrow)
    ctx.drawPath(using: .fillStroke)

    save(ctx, to: path)
    print("wrote \(path)")
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
draw(dark: false, tinted: false, to: "\(out)/AppIcon.png")
draw(dark: true, tinted: false, to: "\(out)/AppIcon-dark.png")
draw(dark: false, tinted: true, to: "\(out)/AppIcon-tinted.png")
