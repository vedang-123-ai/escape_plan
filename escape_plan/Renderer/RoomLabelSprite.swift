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
    private static let renderScale: CGFloat = 3
    /// Keep pathological names from becoming banners across the model.
    private static let maxNameLength = 22

    private final class CacheKey: NSObject {
        let text: String
        let scale: CGFloat

        init(text: String, scale: CGFloat) {
            self.text = text
            self.scale = scale
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? CacheKey else { return false }
            return text == other.text && scale == other.scale
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(text)
            hasher.combine(scale)
            return hasher.finalize()
        }
    }

    private final class CacheBox: NSObject {
        let sprite: Sprite
        init(sprite: Sprite) {
            self.sprite = sprite
        }
    }

    private static let cache = NSCache<CacheKey, CacheBox>()

    /// Clears the in-memory sprite texture cache (e.g. for testing or memory warnings).
    static func clearCache() {
        cache.removeAllObjects()
    }

    /// The room-type accent dot is gone with the White Model overhaul: it was one more hue in a
    /// scene that is meant to have exactly two (route orange, exit green), and rooms are now
    /// identified by their walls and their name, not by color coding.
    static func make(name: String, scale: CGFloat = renderScale) -> Sprite {
        let displayName = name.count > maxNameLength
            ? String(name.prefix(maxNameLength - 1)) + "…"
            : name

        let key = CacheKey(text: displayName, scale: scale)
        if let hit = cache.object(forKey: key) {
            return hit.sprite
        }

        let font = roundedFont(ofSize: fontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: DollhousePalette.labelInk,
        ]
        let textSize = (displayName as NSString).size(withAttributes: attributes)

        let height = ceil(textSize.height + vPadding * 2)
        let width = ceil(hPadding + textSize.width + hPadding)
        let size = CGSize(width: width, height: height)

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let image = renderer.image { context in
            let capsule = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size),
                                       cornerRadius: height / 2)
            // A white chip on a white model: it sits IN the scene rather than floating as UI,
            // and a hairline of label ink gives it just enough edge to separate from the slab.
            UIColor.white.withAlphaComponent(0.85).setFill()
            capsule.fill()
            DollhousePalette.labelInk.withAlphaComponent(0.14).setStroke()
            capsule.lineWidth = 1.5
            capsule.stroke()

            (displayName as NSString).draw(
                at: CGPoint(x: hPadding, y: (height - textSize.height) / 2),
                withAttributes: attributes)

            _ = context // silence unused-parameter lint without discarding the renderer API
        }

        let sprite = Sprite(image: image, aspect: width / height)
        cache.setObject(CacheBox(sprite: sprite), forKey: key)
        return sprite
    }

    private static func roundedFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}
