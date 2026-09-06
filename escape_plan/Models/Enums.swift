// Enums.swift
// Mirrors the enum $defs in schema/homemodel.schema.json.
//
// These stay STRICT — they throw on an unknown value — and that is deliberate, not an
// oversight the 2026-08-02 tolerance sweep missed. The response-only enums
// (ChecklistCategory, WaypointKind, RouteFinding.FindingKind, AgentFinding.Severity) were
// made tolerant that day because they are display-only: the server owns them, the client
// renders them, and a value this build doesn't know costs at most a label.
//
// The enums below are different in kind. They describe the user's own home, they round-trip
// through local JSON persistence, and they are ENCODED as well as decoded. A silent
// `unknown` fallback here would be data loss: decode a room typed "sunroom" from a newer
// build, re-encode it as "other", and the user's home is quietly degraded on disk with no
// error anyone ever saw. Failing loudly is the correct behavior for the contract itself.
//
// This is also why the schema is version-gated (schema_version bump + sign-off + the
// PreToolUse hook): adding a value here is a deliberate, reviewed act, not something the
// backend can do to the client unilaterally. See docs/decisions.md 2026-08-02.

import Foundation

enum RoomType: String, Codable, Equatable, CaseIterable {
    case bedroom, living, kitchen, hall, bath, garage, other
}

enum OpeningKind: String, Codable, Equatable, CaseIterable {
    case door, window
}

enum Source: String, Codable, Equatable, CaseIterable {
    case scan, manual, ai_plan
}

enum ObjectCategory: String, Codable, Equatable, CaseIterable {
    case bed, sofa, table, wardrobe, appliance, storage, other
}

enum StairKind: String, Codable, Equatable, CaseIterable {
    case straight, L, U
}

enum ProfileTag: String, Codable, Equatable, CaseIterable {
    case child, elderly, mobility_limited, pet
    // v2.0. Routing-neutral on purpose: these map to ZERO routing constraints and exist so the
    // readiness checklist can act on them (strobe/bed-shaker alarms, NOAA radio with alert).
    // See docs/profile-constraint-mappings.md.
    case hearing_impaired, vision_impaired
}

/// Utilities a household is advised to locate in advance (v2.0).
/// Landmarks, never obstacles — the routing engine does not see these.
enum SafetyPointKind: String, Codable, Equatable, CaseIterable {
    case gas_shutoff, water_shutoff, electrical_panel
}

/// Whether the household rents or owns (v2.0). Absent means not answered, never "own".
enum Tenure: String, Codable, Equatable, CaseIterable {
    case rent, own
}

/// Safety equipment the household already has (v2.0), so the checklist does not tell
/// someone to buy what is already on their wall.
enum EquipmentItem: String, Codable, Equatable, CaseIterable {
    case smoke_alarm, co_detector, extinguisher, generator
}
