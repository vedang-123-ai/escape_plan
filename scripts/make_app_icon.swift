// Generates the Escape Plan app icon (1024x1024 light/dark/tinted) with CoreGraphics.
//
//   swiftc -O scripts/make_app_icon.swift -o /tmp/make-icon \
//     && /tmp/make-icon escape_plan/Assets.xcassets/AppIcon.appiconset
//
// Motif (DOLLHOUSE-REDESIGN-SPEC §11): a white architectural model of a house, cut open in
// section, with the escape route running through it and out to a green exit pad. It is the
// same visual language as the dollhouse renderer — one white material family, the route as
// the only hot color — so the icon and the app's centerpiece read as the same product.
//
// Replaces the earlier navy/ember icon, which shared no vocabulary with the White Model
// overhaul of 2026-08-05.
//
// Two things the renderer gets for free that an icon does not, and which drive the choices
// below. First, at 40 pt on a home screen there is no ambient occlusion to separate a white
// house from a light gray background, so the silhouette carries a faint edge and a contact
// shadow instead. Second, fine detail disappears entirely — hence four elements and no more:
// house, floor slab, route, exit pad.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = CGSize(width: 1024, height: 1024)

// Content stays inside ~90pt of the edge: iOS masks the icon to a squircle, and anything
// hugging a corner gets clipped.
enum Layout {
    // House silhouette: a body with a gable, as a single pentagon. An overhanging roof reads
    // as mush below ~60 pt. Sat left of centre so the exit pad has ground to sit on without
    // either element crowding the squircle edge.
    static let bodyLeft: CGFloat = 155
    static let bodyRight: CGFloat = 700
    static let bodyBottom: CGFloat = 255
    static let eaves: CGFloat = 615
    static let apex = CGPoint(x: 427, y: 862)

    /// Cut wall faces. Stroked from the silhouette and clipped inward, so the band is half
    /// this wide and the outer edge stays exactly on the silhouette.
    static let wallBand: CGFloat = 76

    static let slab = CGRect(x: bodyLeft, y: 448, width: bodyRight - bodyLeft, height: 40)
    /// Notched out of the right wall — the exterior door the route leaves through.
    static let doorway = CGRect(x: bodyRight - wallBand / 2, y: bodyBottom,
                                width: wallBand / 2, height: 155)

    /// Upper-floor room → down the stairwell → across the ground floor → out the door →
    /// onto the pad. No interior partition: a second white bar at this size is noise, and the
    /// route already implies the rooms it passes through.
    static let route: [CGPoint] = [
        CGPoint(x: 262, y: 555),
        CGPoint(x: 378, y: 555),
        CGPoint(x: 378, y: 350),
        CGPoint(x: 720, y: 350),
        CGPoint(x: 820, y: 292),
    ]
    static let routeWidth: CGFloat = 46
    /// Marks where the route starts, so the first segment reads as an origin rather than as
    /// the handle of an object.
    static let routeOrigin = CGPoint(x: 262, y: 555)
    static let routeOriginRadius: CGFloat = 32

    /// Wide and low, sitting on the ground line outside the door — a pad you step onto, not a
    /// pill on a stick. Drawn AFTER the route so it covers the route's end cap: the path then
    /// reads as arriving at the exit rather than as an orange line with a green tip.
    static let exitPad = CGRect(x: 733, y: 262, width: 172, height: 48)
    static let contactShadow = CGRect(x: 125, y: 212, width: 605, height: 84)

    /// Bounding box of everything above, and the scale that centres it in the canvas with an
    /// iOS-appropriate margin. Laying the artwork out in convenient round numbers and fitting
    /// it afterwards beats nudging twenty coordinates every time the composition changes.
    static let contentBounds = CGRect(x: 125, y: 212, width: 780, height: 650)
    static let contentScale: CGFloat = 1.08
}

struct Palette {
    var backgroundTop: CGColor?
    var backgroundBottom: CGColor?
    /// Recessed interior — the rooms behind the cut.
    var interior: CGColor
    /// Cut wall faces: the brightest surface, exactly as in the renderer.
    var cut: CGColor
    var slabTop: CGColor
    var silhouetteEdge: CGColor?
    var contactShadow: CGColor?
    var route: CGColor
    var exit: CGColor
}

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    rgba(CGFloat((value >> 16) & 0xFF) / 255,
         CGFloat((value >> 8) & 0xFF) / 255,
         CGFloat(value & 0xFF) / 255, alpha)
}

// DollhousePalette.swift, kept in sync by hand — the icon is generated once, not at runtime.
let light = Palette(
    backgroundTop: hex(0xE9E8E6), backgroundBottom: hex(0xD9D6D1),
    interior: hex(0xEDEBE6), cut: hex(0xFCFBF9), slabTop: hex(0xFFFFFF),
    silhouetteEdge: hex(0xD3CFC8), contactShadow: hex(0xB9B5AF, 0.38),
    route: hex(0xFF5A1F), exit: hex(0x16A34A))

let dark = Palette(
    backgroundTop: hex(0x2A2725), backgroundBottom: hex(0x171614),
    interior: hex(0xD7D4CD), cut: hex(0xF4F2ED), slabTop: hex(0xFFFFFF),
    silhouetteEdge: hex(0x0F0E0D, 0.5), contactShadow: hex(0x000000, 0.45),
    route: hex(0xFF6B33), exit: hex(0x22C55E))

// Tinted icons are composited by iOS from luminance alone, so the palette collapses to a
// grayscale hierarchy: route brightest (it is the subject), then the cut faces, then the
// recessed interior. Background must stay clear — iOS supplies its own.
let tinted = Palette(
    backgroundTop: nil, backgroundBottom: nil,
    interior: rgba(1, 1, 1, 0.42), cut: rgba(1, 1, 1, 0.80), slabTop: rgba(1, 1, 1, 0.92),
    silhouetteEdge: nil, contactShadow: nil,
    route: rgba(1, 1, 1, 1.0), exit: rgba(1, 1, 1, 0.66))

func makeContext() -> CGContext {
    CGContext(data: nil, width: Int(size.width), height: Int(size.height),
              bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func housePath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: Layout.bodyLeft, y: Layout.bodyBottom))
    path.addLine(to: CGPoint(x: Layout.bodyRight, y: Layout.bodyBottom))
    path.addLine(to: CGPoint(x: Layout.bodyRight, y: Layout.eaves))
    path.addLine(to: Layout.apex)
    path.addLine(to: CGPoint(x: Layout.bodyLeft, y: Layout.eaves))
    path.closeSubpath()
    return path
}

func routePath() -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: Layout.route)
    return path
}

func draw(_ palette: Palette, to path: String) {
    let ctx = makeContext()
    let full = CGRect(origin: .zero, size: size)
    ctx.clear(full)

    if let top = palette.backgroundTop, let bottom = palette.backgroundBottom {
        let gradient = CGGradient(colorsSpace: nil, colors: [top, bottom] as CFArray,
                                  locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 1024),
                               end: CGPoint(x: 512, y: 0), options: [])
    }

    // Everything from here on is drawn in layout space and fitted to the canvas as a unit.
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 512)
    ctx.scaleBy(x: Layout.contentScale, y: Layout.contentScale)
    ctx.translateBy(x: -Layout.contentBounds.midX, y: -Layout.contentBounds.midY)

    // Grounding: the soft darkening under the model, same job as the renderer's contact plane.
    if let shadow = palette.contactShadow {
        ctx.setFillColor(shadow)
        ctx.fillEllipse(in: Layout.contactShadow)
    }

    let house = housePath()

    ctx.setFillColor(palette.interior)
    ctx.addPath(house)
    ctx.fillPath()

    // Cut wall faces. Clipping to the silhouette turns a centered stroke into an inward band,
    // so the outer edge stays crisp on the gable.
    ctx.saveGState()
    ctx.addPath(house)
    ctx.clip()
    ctx.setStrokeColor(palette.cut)
    ctx.setLineWidth(Layout.wallBand)
    // Round, not miter: a mitered join at the gable apex spikes past the silhouette and gets
    // sheared off by the clip, leaving a visible notch at the roof peak.
    ctx.setLineJoin(.round)
    ctx.addPath(house)
    ctx.strokePath()

    ctx.setFillColor(palette.cut)
    ctx.fill(Layout.slab)
    // The slab's top face is the brightest line in the icon — it is what makes the model read
    // as sliced open rather than as a flat house glyph.
    ctx.setFillColor(palette.slabTop)
    ctx.fill(CGRect(x: Layout.slab.minX, y: Layout.slab.maxY - 8,
                    width: Layout.slab.width, height: 8))

    // Notch the doorway back out of the wall band.
    ctx.setFillColor(palette.interior)
    ctx.fill(Layout.doorway)
    ctx.restoreGState()

    if let edge = palette.silhouetteEdge {
        ctx.setStrokeColor(edge)
        ctx.setLineWidth(5)
        ctx.setLineJoin(.round)
        ctx.addPath(house)
        ctx.strokePath()
    }

    ctx.setStrokeColor(palette.route)
    ctx.setLineWidth(Layout.routeWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(routePath())
    ctx.strokePath()

    ctx.setFillColor(palette.route)
    ctx.fillEllipse(in: CGRect(x: Layout.routeOrigin.x - Layout.routeOriginRadius,
                               y: Layout.routeOrigin.y - Layout.routeOriginRadius,
                               width: Layout.routeOriginRadius * 2,
                               height: Layout.routeOriginRadius * 2))

    ctx.setFillColor(palette.exit)
    ctx.addPath(CGPath(roundedRect: Layout.exitPad, cornerWidth: 24, cornerHeight: 24,
                       transform: nil))
    ctx.fillPath()

    ctx.restoreGState()

    let image = ctx.makeImage()!
    let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("wrote \(path)")
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
draw(light, to: "\(out)/AppIcon.png")
draw(dark, to: "\(out)/AppIcon-dark.png")
draw(tinted, to: "\(out)/AppIcon-tinted.png")
