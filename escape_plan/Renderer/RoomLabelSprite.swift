//  RoomLabelSprite.swift
//  escape_plan
//
//  Renders a room label as a capsule chip image for the dollhouse (UI craft pass, Jul 2026).
//  SCNText gave hairline, unpadded glyphs that disappeared against the walls; a pre-rendered
//  chip gives the label a legible surface, real padding, and a room-type accent dot — the
//  same vocabulary as the app's capsule chips, so the scene and the chrome speak one language.
//
//  The image is drawn at 3× and mapped onto an SCNPlane by the scene builder; alpha in the
//  image carries the capsule shape, so the plane itself needs no corner geometry.

import UIKit

enum RoomLabelSprite {

    struct Sprite {
        let image: UIImage
        /// width / height — the scene builder sizes the plane from this.
        let aspect: CGFloat
    }

    /// Layout constants in sprite points (rendered at `renderScale`).
    private static let fontSize: CGFloat = 30
    private static let hPadding: CGFloat = 18
    private static let vPadding: CGFloat = 10
    private static let dotDiameter: CGFloat = 12
    private static let dotGap: CGFloat = 9
    private static let renderScale: CGFloat = 3
    /// Keep pathological names from becoming banners across the model.
    private static let maxNameLength = 22

    static func make(name: String, accent: UIColor) -> Sprite {
        let displayName = name.count > maxNameLength
            ? String(name.prefix(maxNameLength - 1)) + "…"
            : name

        let font = roundedFont(ofSize: fontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: DollhousePalette.label,
        ]
        let textSize = (displayName as NSString).size(withAttributes: attributes)

        let height = ceil(textSize.height + vPadding * 2)
        let width = ceil(hPadding + dotDiameter + dotGap + textSize.width + hPadding)
        let size = CGSize(width: width, height: height)

        let format = UIGraphicsImageRendererFormat()
        format.scale = renderScale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let image = renderer.image { context in
            let capsule = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size),
                                       cornerRadius: height / 2)
            // Warm paper surface, slightly translucent so the chip sits IN the diorama
            // rather than floating as UI; hairline in the label ink for edge definition.
            DollhousePalette.background.withAlphaComponent(0.94).setFill()
            capsule.fill()
            DollhousePalette.label.withAlphaComponent(0.14).setStroke()
            capsule.lineWidth = 1.5
            capsule.stroke()

            let dotRect = CGRect(x: hPadding,
                                 y: (height - dotDiameter) / 2,
                                 width: dotDiameter, height: dotDiameter)
            accent.setFill()
            UIBezierPath(ovalIn: dotRect).fill()

            (displayName as NSString).draw(
                at: CGPoint(x: hPadding + dotDiameter + dotGap,
                            y: (height - textSize.height) / 2),
                withAttributes: attributes)

            _ = context // silence unused-parameter lint without discarding the renderer API
        }

        return Sprite(image: image, aspect: width / height)
    }

    private static func roundedFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}
