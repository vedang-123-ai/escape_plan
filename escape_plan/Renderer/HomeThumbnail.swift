//  HomeThumbnail.swift
//  Renderer — offscreen dollhouse renders for the homes list.
//
//  The list used to show every home as two lines of text, so the one thing that makes a home
//  recognisable — its shape — was invisible until you opened it. These are real renders of the
//  real model through the real builder, not illustrations: a home with three floors looks like
//  a home with three floors, and the White Model language is the same one the House tab uses.
//
//  Rendering goes through `SCNRenderer` rather than snapshotting an `SCNView`, because there is
//  no view here: SCNRenderer is the offscreen path and doesn't need to be in a window.

import SceneKit
import UIKit

enum HomeThumbnail {

    /// Renders `home` at `size` points × `scale`. Returns nil only if Metal is unavailable,
    /// which on a real device or simulator does not happen.
    ///
    /// Must run on the main actor: it builds a scene graph, and SceneKit is not thread-safe.
    @MainActor
    static func render(_ home: HomeModel, size: CGSize, scale: CGFloat) -> UIImage? {
        guard size.width > 0, size.height > 0,
              let device = MTLCreateSystemDefaultDevice() else { return nil }

        let built = DollhouseSceneBuilder.build(home)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = built.dollhouse.scene
        renderer.pointOfView = built.dollhouse.cameraNode

        // Shadow maps and SSAO are tuned for a full-screen view. At ~74×54 pt the shadow map
        // samples far below its own texel density and the result is speckled acne across every
        // wall face — the tile reads as noise rather than as a clean white model. Ambient light
        // takes over the shadow's share so the model doesn't just go flat and dark.
        built.dollhouse.scene.rootNode.enumerateHierarchy { node, _ in
            guard let light = node.light else { return }
            if light.castsShadow {
                light.castsShadow = false
            }
            if light.type == .ambient {
                light.intensity *= 1.25
            }
        }

        // The builder frames for a roughly square viewport, and `orthographicScale` is a
        // half-HEIGHT — the same trap the camera rig hit. A wide thumbnail therefore fits
        // vertically with slack to spare; a tall one would crop, so widen by the aspect there.
        // The 0.86 tightens the framing: the builder leaves margin for on-screen chrome that a
        // tile doesn't have, so without it the house sits small in its own thumbnail.
        if let camera = built.dollhouse.cameraNode.camera {
            camera.screenSpaceAmbientOcclusionIntensity = 0
            if camera.usesOrthographicProjection {
                let aspect = size.width / size.height
                camera.orthographicScale *= 0.86
                if aspect < 1 { camera.orthographicScale /= Double(aspect) }
            }
        }

        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        let image = renderer.snapshot(atTime: 0, with: pixels, antialiasingMode: .multisampling4X)
        return UIImage(cgImage: image.cgImage!, scale: scale, orientation: .up)
    }
}
