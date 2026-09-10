import SwiftUI

struct HazardHuntView: View {
    let store: HomeModelStore
    @State private var isHunting = false
    @State private var currentRoomIndex = 0
    @State private var questionIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isHunting {
                Button {
                    startHunt()
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Start Hazard Hunt")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: DS.buttonRadius, style: .continuous)
                            .strokeBorder(Theme.accent, lineWidth: 1.5)
                    )
                }
                .buttonStyle(DSPressStyle())
                .accessibilityIdentifier("house.hazardHunt.start")
            } else {
                huntFlow
            }
        }
    }
    
    private struct RoomRef {
        let room: Room
        let floorId: String
    }
    
    private var roomsToHunt: [RoomRef] {
        store.model.floors.flatMap { floor in
            floor.rooms.map { RoomRef(room: $0, floorId: floor.id) }
        }
    }
    
    private var activeRoomRef: RoomRef? {
        let rooms = roomsToHunt
        guard currentRoomIndex < rooms.count else { return nil }
        return rooms[currentRoomIndex]
    }
    
    private var huntFlow: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let ref = activeRoomRef {
                let qs = questions(for: ref)
                if questionIndex < qs.count {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Hazard Hunt: \(ref.room.name)")
                            .font(.headline)
                            .foregroundStyle(DS.ink)
                        Text(qs[questionIndex].text)
                            .font(.body)
                            .foregroundStyle(DS.bodyInk)
                            .accessibilityIdentifier("house.hazardHunt.questionText")
                        HStack(spacing: 12) {
                            Button("Yes") {
                                qs[questionIndex].applyYes(store, ref)
                                nextQuestion()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                            .accessibilityIdentifier("house.hazardHunt.yes")
                            
                            Button("No") {
                                nextQuestion()
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("house.hazardHunt.no")
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.card, in: RoundedRectangle(cornerRadius: DS.cardRadius))
                } else {
                    Text("Done with \(ref.room.name)!")
                        .padding()
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                nextRoom()
                            }
                        }
                }
            } else {
                VStack(spacing: 16) {
                    Text("Hazard Hunt Complete!")
                        .font(.headline)
                    Button("Done") {
                        isHunting = false
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("house.hazardHunt.done")
                }
                .padding()
            }
        }
    }
    
    private func startHunt() {
        currentRoomIndex = 0
        questionIndex = 0
        isHunting = true
        focusRoom()
    }
    
    private func nextQuestion() {
        if let ref = activeRoomRef, questionIndex < questions(for: ref).count - 1 {
            questionIndex += 1
        } else {
            nextRoom()
        }
    }
    
    private func nextRoom() {
        currentRoomIndex += 1
        questionIndex = 0
        if activeRoomRef != nil {
            focusRoom()
        }
    }
    
    private func focusRoom() {
        if let ref = activeRoomRef {
            store.setActiveFloor(ref.floorId)
            store.select(.room(roomId: ref.room.id))
        }
    }
    
    private struct HuntQuestion {
        let text: String
        let applyYes: (HomeModelStore, RoomRef) -> Void
    }
    
    private func center(of polygon: Polygon) -> Point {
        guard !polygon.isEmpty else { return Point(x: 0, y: 0) }
        let sumX = polygon.map(\.x).reduce(0, +)
        let sumY = polygon.map(\.y).reduce(0, +)
        return Point(x: sumX / Double(polygon.count), y: sumY / Double(polygon.count))
    }
    
    private func questions(for ref: RoomRef) -> [HuntQuestion] {
        var qs: [HuntQuestion] = []
        let room = ref.room
        
        let roomCenter = center(of: room.polygon)
        
        qs.append(HuntQuestion(text: "Portable heater here?") { store, ref in
            let id = UUID().uuidString
            store.dispatch(.addObject(objectId: id, floorId: ref.floorId, category: .heat_source, center: roomCenter, size_m: [0.3, 0.3], height_m: 0.5))
            store.select(.object(objectId: id))
        })
        
        if room.type == .bedroom {
            qs.append(HuntQuestion(text: "Anything tall and heavy near the bed?") { store, ref in
                let id = UUID().uuidString
                store.dispatch(.addObject(objectId: id, floorId: ref.floorId, category: .bookcase, center: roomCenter, size_m: [0.8, 0.4], height_m: 1.8))
                store.select(.object(objectId: id))
            })
            qs.append(HuntQuestion(text: "Anything mounted above it?") { store, ref in
                let id = UUID().uuidString
                store.dispatch(.addObject(objectId: id, floorId: ref.floorId, category: .tv, center: roomCenter, size_m: [1.0, 0.1], height_m: 0.6))
                store.dispatch(.setObjectMounted(objectId: id, mounted: true))
                store.dispatch(.setObjectElevation(objectId: id, elevation_m: 1.5))
                store.select(.object(objectId: id))
            })
        }
        
        if room.type == .garage || room.name.lowercased().contains("utility") {
            qs.append(HuntQuestion(text: "Water heater — strapped?") { store, ref in
                let id = UUID().uuidString
                store.dispatch(.addObject(objectId: id, floorId: ref.floorId, category: .water_heater, center: roomCenter, size_m: [0.6, 0.6], height_m: 1.5))
                store.dispatch(.setObjectSecured(objectId: id, secured: true))
                store.select(.object(objectId: id))
            })
        }
        
        return qs
    }
}
