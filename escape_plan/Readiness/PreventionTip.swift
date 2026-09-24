//  PreventionTip.swift
//  escape_plan — Readiness (S11.5)
//
//  Swift mirror of one entry in `backend/corpus/prevention_tips.json` (bundled byte-identical
//  at `escape_plan/Resources/prevention_tips.json`; `scripts/check-tips-sync.py` enforces the
//  two stay equal). Foundation-only — this file is symlinked into `tools/editorcore` so its
//  decode and filter logic runs under `swift test`, no simulator required. SwiftUI rendering
//  lives in Screens/HomeScreen.swift, never here (.claude/rules/paths/editorcore.md).

import Foundation

/// One prevention/readiness tip. `cite` is non-optional on purpose: the corpus rule
/// (.claude/rules/paths/corpus.md) is "no source, it doesn't ship" — a tip missing a citation
/// must fail to decode rather than render uncited.
struct PreventionTip: Codable, Identifiable, Hashable {
    var id: String
    var peril: Peril
    var topic: String
    var text: String
    /// Corpus source id, resolved against `backend/corpus/sources.json` server-side
    /// (validate.py). The client never re-validates; it only displays the id it was shipped.
    var cite: String
    var audience: Audience

    /// The three locked perils (see CLAUDE.md "Scope lock"). Kept as a strict enum — unlike
    /// `Audience` below — because a fourth peril appearing here would itself be a scope-lock
    /// violation worth a hard decode failure, not a silently-dropped tip.
    enum Peril: String, Codable, CaseIterable {
        case fire
        case earthquake
        case tornado
    }

    /// Tolerant on purpose, following `ChecklistCategory`'s precedent in ScoreModels.swift: a
    /// raw-value enum that throws on an unknown case fails the WHOLE tips array's decode over
    /// one new audience tag the corpus added after this build shipped. `.other` absorbs it
    /// instead of taking down every tip.
    enum Audience: String, Codable, CaseIterable {
        case everyone
        case renters
        case householdsWithChildren = "households-with-children"
        case mobileHome = "mobile-home"
        case deafHardOfHearing = "deaf-hard-of-hearing"
        case california
        case other

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Audience(rawValue: raw) ?? .other
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(self.rawValue)
        }
    }
}

/// The top-level shape of prevention_tips.json. Decoding through the whole payload (rather
/// than hand-slicing the `tips` array out of raw JSON) means a shape drift between the corpus
/// file and this mirror fails loudly here instead of silently dropping fields.
struct PreventionTipsPayload: Codable {
    var schema_version: String
    var tips: [PreventionTip]
}

enum PreventionTips {
    static func decode(from data: Data) throws -> [PreventionTip] {
        try JSONDecoder().decode(PreventionTipsPayload.self, from: data).tips
    }
}
