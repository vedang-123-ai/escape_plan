import SwiftUI

struct DiffResultWrapper: Identifiable {
    let id = UUID()
    let result: DiffResult
}

struct DiffReviewSheet: View {
    let result: DiffResult
    let onAdd: (FloorObject) -> Void
    let onDismiss: () -> Void
    
    @State private var addedIds = Set<String>()
    @State private var dismissedIds = Set<String>()

    var body: some View {
        NavigationStack {
            List {
                if result.diff_objects.isEmpty {
                    Text("No new objects detected in the scanned area.")
                } else {
                    let activeObjects = result.diff_objects.filter { !addedIds.contains($0.id) && !dismissedIds.contains($0.id) }
                    if activeObjects.isEmpty {
                        Text("All items reviewed.")
                    } else {
                        ForEach(activeObjects) { obj in
                            VStack(alignment: .leading, spacing: 12) {
                                Text("New Object Detected")
                                    .font(.headline)
                                
                                if let obstruction = result.obstructions.first(where: { $0.object_ids.contains(obj.id) }) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.red)
                                        Text(obstruction.kind.replacingOccurrences(of: "_", with: " ").capitalized)
                                            .font(.subheadline)
                                            .foregroundStyle(.red)
                                    }
                                    Text("Passable width: \(String(format: "%.2f", obstruction.passable_width_m))m (required: \(String(format: "%.2f", obstruction.required_width_m))m)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("No obstruction detected.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                
                                HStack {
                                    Button("Add to Home") {
                                        onAdd(obj)
                                        addedIds.insert(obj.id)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    
                                    Button("Dismiss", role: .cancel) {
                                        dismissedIds.insert(obj.id)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Re-check Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
    }
}
