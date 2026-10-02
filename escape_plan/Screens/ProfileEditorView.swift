//  ProfileEditorView.swift
//  escape_plan
//
//  S3.4 create/edit form for one family profile, presented as a sheet from ProfilesScreen.
//  Pure form over a model snapshot — all mutation happens in the caller via EditAction
//  dispatch, so validation/undo/autosave come for free from HomeModelStore.

import SwiftUI

struct ProfileEditorView: View {
    /// Read-only snapshot for the bedroom picker.
    let model: HomeModel
    /// nil = creating a new profile.
    let existing: Profile?
    /// Returns true if the store accepted the mutation; false keeps the sheet open.
    let onSave: (_ name: String, _ tags: Set<ProfileTag>, _ bedroomRoomId: String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var tags: Set<ProfileTag>
    @State private var bedroomRoomId: String

    init(model: HomeModel, existing: Profile?,
         onSave: @escaping (_ name: String, _ tags: Set<ProfileTag>, _ bedroomRoomId: String) -> Bool) {
        self.model = model
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _tags = State(initialValue: Set(existing?.tags ?? []))
        _bedroomRoomId = State(initialValue: existing?.bedroom_room_id
                               ?? Self.defaultBedroom(in: model))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // The system placeholder is ~2.4:1 on a sheet's form row.
                    TextField("Name", text: $name,
                              prompt: Text("Name").foregroundStyle(Theme.supporting))
                        .accessibilityLabel("Name")
                        .accessibilityHint("The name of the person or pet who lives here.")
                } header: {
                    Text("Name").accessibilityAddTraits(.isHeader)
                }
                Section {
                    ForEach(ProfileTag.allCases, id: \.self) { tag in
                        Toggle(tag.displayName, isOn: Binding(
                            get: { tags.contains(tag) },
                            set: { on in if on { tags.insert(tag) } else { tags.remove(tag) } }
                        ))
                        .accessibilityLabel(tag.displayName)
                        .accessibilityValue(tags.contains(tag) ? "On" : "Off")
                        .accessibilityHint(tag.routingHint)
                        // The app tint's "on" track is 2.97:1 on a form row; accentText is 5:1.
                        .tint(Theme.accentText)
                    }
                } header: {
                    Text("Needs").accessibilityAddTraits(.isHeader)
                } footer: {
                    Text("Tags shape this person's escape routes — e.g. limited mobility avoids stairs and windows.")
                }
                Section {
                    Picker("Bedroom", selection: $bedroomRoomId) {
                        ForEach(model.floorsByLevel) { floor in
                            Section(floor.name.isEmpty ? "Level \(floor.level)" : floor.name) {
                                ForEach(floor.rooms) { room in
                                    roomOption(room)
                                }
                            }
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityLabel("Bedroom")
                    .accessibilityValue(model.locateRoom(bedroomRoomId)?.room.name
                                        ?? "Not chosen")
                    .accessibilityHint("Escape routes are computed from where this person "
                                       + "sleeps, so pick the room they're in at night.")
                } header: {
                    Text("Bedroom").accessibilityAddTraits(.isHeader)
                }
            }
            .navigationTitle(existing == nil ? "New Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Accent text is under 4.5:1 on a sheet; accentText passes.
                    Button("Cancel") { dismiss() }
                        .tint(Theme.accentText)
                        .accessibilityHint("Closes without saving this profile.")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if onSave(name.trimmingCharacters(in: .whitespaces), tags, bedroomRoomId) {
                            dismiss()
                        }
                    }
                    .tint(Theme.accentText)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityHint(name.trimmingCharacters(in: .whitespaces).isEmpty
                                       ? "Unavailable until you enter a name."
                                       : "Saves this profile. Their escape routes are planned from it.")
                }
            }
        }
    }

    /// One row of the bedroom picker. Extracted because the inline ternary-in-a-Label inside
    /// two nested ForEach/Section pairs blows the SwiftUI type-checker's budget.
    private func roomOption(_ room: Room) -> some View {
        let symbol = room.type == .bedroom ? "bed.double" : "square.dashed"
        return Label(room.name, systemImage: symbol)
            .tag(room.id)
            .accessibilityLabel(room.name)
    }

    /// Suggest a bedroom-typed room if the home has one; otherwise the first room of the
    /// lowest floor. A zero-room home is impossible (schema: every floor has >= 1 room).
    private static func defaultBedroom(in model: HomeModel) -> String {
        let ordered = model.floorsByLevel
        if let bedroom = ordered.flatMap(\.rooms).first(where: { $0.type == .bedroom }) {
            return bedroom.id
        }
        return ordered.first!.rooms.first!.id
    }
}

extension ProfileTag {
    /// Human-readable label for the tag toggles and list chips. Kept here (not Enums.swift)
    /// so Models/ stays a pure schema mirror.
    var displayName: String {
        switch self {
        case .child: return "Child"
        case .elderly: return "Elderly"
        case .mobility_limited: return "Limited Mobility"
        case .pet: return "Pet"
        case .hearing_impaired: return "Hearing Impaired"
        case .vision_impaired: return "Vision Impaired"
        }
    }

    /// What turning this tag on actually does to the route. VoiceOver's hint is the only place
    /// a non-sighted user can learn that "Limited Mobility" is a routing constraint and not a
    /// label — the visible footer says it once for the whole section, which a screen reader
    /// reaches only after all four switches.
    ///
    /// These sentences must stay true to `backend/app/routing/profiles.py`
    /// (`constraints_for_profile`) — they describe the deterministic engine's behaviour, not a
    /// safety opinion. Hard constraint vs soft preference is the distinction that matters.
    var routingHint: String {
        switch self {
        case .child:
            return "Routes out of a window are used only as a last resort."
        case .elderly:
            return "Stair-free routes are preferred where one exists."
        case .mobility_limited:
            return "Stairs and window exits are never used."
        case .pet:
            return "Listed on the plan. Doesn't change how routes are computed."
        case .hearing_impaired:
            return "Changes no routing."
        case .vision_impaired:
            return "Changes no routing."
        }
    }
}
