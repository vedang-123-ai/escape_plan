//  CountPhrase.swift
//  escape_plan — Readiness (S11.57, defect S53-5)
//
//  "1 issue", "2 issues", "1 item", "0 items": a number and a noun that agree. VoiceOver read
//  "1 issues" and "Done, 1 items" because each screen glued an "s" on by hand. Every count spoken
//  or shown with a noun goes through here. Foundation-only, symlinked into tools/editorcore.

import Foundation

enum CountPhrase {
    /// "1 room", "3 rooms". `plural` defaults to `singular` + "s"; pass it for irregular nouns
    /// ("1 person", "2 people").
    static func of(_ count: Int, _ singular: String, plural: String? = nil) -> String {
        "\(count) \(count == 1 ? singular : (plural ?? singular + "s"))"
    }
}
