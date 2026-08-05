//  HomeThumbnailView.swift
//  Screens — the homes list's live 3D preview tile.
//
//  Renders lazily (only rows that appear), off the main runloop tick via `.task`, and caches
//  by home id + modification date so scrolling back up is free and an edited home re-renders
//  exactly once.

import SwiftUI

struct HomeThumbnailView: View {
    let summary: HomeSummary
    let store: HomeDocumentStore

    static let size = CGSize(width: 74, height: 54)

    @State private var image: UIImage?
    @State private var failed = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(DollhousePalette.background))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if failed {
                // A home whose document won't load still gets a row; the tile just says so
                // rather than spinning forever.
                Image(systemName: "house")
                    .foregroundStyle(Theme.supporting)
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .accessibilityHidden(true)
        // Keyed on `modified`, so editing a home invalidates its tile and nothing else does.
        .task(id: summary.modified) { await load() }
    }

    private func load() async {
        if let cached = Self.cache[Self.key(for: summary)] {
            image = cached
            return
        }
        guard let home = try? store.load(homeID: summary.id, as: HomeModel.self) else {
            failed = true
            return
        }
        // Yield first so a fast scroll doesn't render tiles that are already gone.
        await Task.yield()
        guard !Task.isCancelled else { return }

        let rendered = HomeThumbnail.render(home, size: Self.size, scale: displayScale)
        guard !Task.isCancelled else { return }
        if let rendered {
            Self.remember(rendered, for: summary)
            image = rendered
        } else {
            failed = true
        }
    }

    // MARK: - Cache

    /// Small and process-local on purpose. Thumbnails are cheap to regenerate and there are
    /// only ever a handful of homes, so a disk cache would be more invalidation risk than win.
    @MainActor private static var cache: [String: UIImage] = [:]
    @MainActor private static var order: [String] = []
    private static let limit = 24

    private static func key(for summary: HomeSummary) -> String {
        "\(summary.id)@\(summary.modified.timeIntervalSince1970)"
    }

    @MainActor
    private static func remember(_ image: UIImage, for summary: HomeSummary) {
        let key = key(for: summary)
        // Drop any older render of the same home — only the current revision is useful.
        order.removeAll { $0.hasPrefix("\(summary.id)@") }
        cache = cache.filter { !$0.key.hasPrefix("\(summary.id)@") }
        cache[key] = image
        order.append(key)
        while order.count > limit, let oldest = order.first {
            order.removeFirst()
            cache[oldest] = nil
        }
    }
}
