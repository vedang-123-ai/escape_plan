with open("escape_plan/Screens/HomeScreen.swift", "r") as f:
    c = f.read()

import re

# Add state variables
state_vars = """    @State private var showingRoomPicker = false
    @State private var pendingDiffResult: DiffResult?
    @State private var pendingRecheckRoomID: String?
"""
c = c.replace("@State private var targetRecheckRoomID: String? = nil", "@State private var targetRecheckRoomID: String? = nil\n" + state_vars)

# Fix ChecklistItemSheet secondary action
old_sheet = """                           secondary: item.id == "practice.drill_recent" ? ChecklistRowAction(title: "Re-check with the camera", icon: "camera.viewfinder", navigates: false) : nil,
                               onSecondary: item.id == "practice.drill_recent" ? { detailItem = nil; targetRecheckRoomID = getPrimaryRouteCorridor(); showingScan = true } : nil)"""
new_sheet = """                           secondary: item.id == "routes.corridors_clear" ? ChecklistRowAction(title: "Re-check with the camera", icon: "camera.viewfinder", navigates: false) : nil,
                               onSecondary: item.id == "routes.corridors_clear" ? { detailItem = nil; showingRoomPicker = true } : nil)"""
c = c.replace(old_sheet, new_sheet)

# Add room picker dialog
picker_dialog = """            .confirmationDialog("Select a room to re-check", isPresented: $showingRoomPicker, titleVisibility: .visible) {
                if let activeHome {
                    ForEach(activeHome.floors.flatMap(\.rooms)) { room in
                        Button(room.name) {
                            targetRecheckRoomID = room.id
                            showingScan = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            }"""
c = c.replace(".sheet(isPresented: $showingBuildFromPlan) {", picker_dialog + "\n            .sheet(isPresented: $showingBuildFromPlan) {")

# Add diff review sheet
diff_sheet = """            .sheet(item: Binding<DiffResultWrapper?>(
                get: {
                    if let res = pendingDiffResult { return DiffResultWrapper(result: res) }
                    return nil
                },
                set: { if $0 == nil { pendingDiffResult = nil } }
            )) { wrapper in
                DiffReviewSheet(
                    result: wrapper.result,
                    onAdd: { obj in
                        guard var home = activeHome, let roomID = pendingRecheckRoomID else { return }
                        if let floorIdx = home.floors.firstIndex(where: { $0.rooms.contains(where: { $0.id == roomID }) }) {
                            home.floors[floorIdx].objects.append(obj)
                            // Use EditAction to mutate
                            let docStore = try? HomeDocumentStore()
                            try? docStore?.save(model: home)
                            activeHome = home
                            Task { await fetchScore() }
                        }
                    },
                    onDismiss: { pendingDiffResult = nil; pendingRecheckRoomID = nil }
                )
            }"""
c = c.replace(".sheet(isPresented: $showingBuildFromPlan) {", diff_sheet + "\n            .sheet(isPresented: $showingBuildFromPlan) {")

# Replace processRecheck
old_process = """    private func processRecheck(artifacts: ScanArtifacts, roomID: String) async {
        isConverting = true
        defer { isConverting = false }
        do {
            guard var activeHome = activeHome else { return }
            let scanModel = try await apiClient.convertScan(at: artifacts.rawJSON, homeName: "Recheck")
            let diffRequest = DiffRequest(stored_model: activeHome, scan_model: scanModel, target_room_id: roomID)
            let result = try await apiClient.diffObstructions(diffRequest)
            
            // If we found any new obstructions, we want to inform the user. For now just show alert or update model?
            // Actually, S7.8 just says "if a new object intrudes on the route corridor or an opening approach, say so."
            // The score breakdown will re-fetch if we update the model! So we just save the new injected model.
            // But wait, the diff endpoint returns DiffResult. We can inject the diff_objects into the activeHome.
            if let targetFloorIdx = activeHome.floors.firstIndex(where: { $0.rooms.contains(where: { $0.id == roomID }) }) {
                activeHome.floors[targetFloorIdx].objects.append(contentsOf: result.diff_objects)
                try library.store.save(model: activeHome)
                await fetchScore()
            }
        } catch {
            scanFailure = BackendFailure(error, while: .score)
        }
    }"""
new_process = """    private func processRecheck(artifacts: ScanArtifacts, roomID: String) async {
        isConverting = true
        defer { isConverting = false }
        do {
            guard let activeHome = activeHome else { return }
            let scanModel = try await apiClient.convertScan(at: artifacts.rawJSON, homeName: "Recheck")
            let diffRequest = DiffRequest(stored_model: activeHome, scan_model: scanModel, target_room_id: roomID)
            let result = try await apiClient.diffObstructions(diffRequest)
            pendingRecheckRoomID = roomID
            pendingDiffResult = result
        } catch {
            scanFailure = BackendFailure(error, while: .score)
        }
    }"""
c = c.replace(old_process, new_process)

# Delete getPrimaryRouteCorridor
c = re.sub(r'    private func getPrimaryRouteCorridor.*?^    }', '', c, flags=re.MULTILINE | re.DOTALL)

with open("escape_plan/Screens/HomeScreen.swift", "w") as f:
    f.write(c)

