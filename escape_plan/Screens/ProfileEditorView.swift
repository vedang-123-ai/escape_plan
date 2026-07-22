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
                Section("Name") {
                    TextField("Name", text: $name)
                }
                Section {
                    ForEach(ProfileTag.allCases, id: \.self) { tag in
                        Toggle(tag.displayName, isOn: Binding(
                            get: { tags.contains(tag) },
                            set: { on in if on { tags.insert(tag) } else { tags.remove(tag) } }
                        ))
                    }
                } header: {
                    Text("Needs")
                } footer: {
                    Text("Tags shape this person's escape routes — e.g. limited mobility avoids stairs and windows.")
                }
                Section("Bedroom") {
                    Picker("Bedroom", selection: $bedroomRoomId) {
                        ForEach(model.floorsByLevel) { floor in
                            Section(floor.name.isEmpty ? "Level \(floor.level)" : floor.name) {
                                ForEach(floor.rooms) { room in
                                    Label(room.name,
                                          systemImage: room.type == .bedroom ? "bed.double" : "square.dashed")
                                        .tag(room.id)
                                }
                            }
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }
            .navigationTitle(existing == nil ? "New Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if onSave(name.trimmingCharacters(in: .whitespaces), tags, bedroomRoomId) {
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
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
        }
    }
}
