// OnboardingState.swift

import Foundation
import Observation

@Observable
@MainActor
final class OnboardingState {
    enum Step {
        case welcome
        case whoLivesHere
        case needs
        case rentOrOwn
        case done
    }

    var step: Step = .welcome

    struct Person: Identifiable, Equatable {
        let id = UUID().uuidString
        var name: String = ""
        var age: String = ""
        var mobilityLimited: Bool = false
        var hearingImpaired: Bool = false
        var visionImpaired: Bool = false
    }

    var persons: [Person] = [Person()]
    var tenure: Tenure? = nil

    private(set) var seededHome: HomeModel?
    private(set) var seedError: String?

    func seedIfNeeded() {
        guard seededHome == nil else { return }
        do {
            seededHome = try FixtureSeeder.seedDemoHome(into: try HomeDocumentStore())
            seedError = nil
        } catch {
            seedError = "Couldn't create the demo home: \(error.localizedDescription)"
        }
    }

    func cancelWork() {
        // No longer running /analyze in background during onboarding.
    }

    func commitAndFinish() {
        guard let home = seededHome else { return }
        
        let ordered = home.floors.sorted { $0.level < $1.level }
        let defaultBedroom = ordered.flatMap(\.rooms).first(where: { $0.type == .bedroom })?.id 
            ?? ordered.first?.rooms.first?.id ?? ""
            
        do {
            let documentStore = try HomeDocumentStore()
            let store = try HomeModelStore(model: home)
            
            store.onCommit = { commit in
                do {
                    try documentStore.save(model: commit.after)
                } catch {
                    print("Failed to save profiles to seeded home: \(error)")
                }
            }
            
            for p in persons {
                var tags: [ProfileTag] = []
                if let ageInt = Int(p.age) {
                    if ageInt <= 12 { tags.append(.child) }
                    else if ageInt >= 65 { tags.append(.elderly) }
                }
                if p.mobilityLimited { tags.append(.mobility_limited) }
                if p.hearingImpaired { tags.append(.hearing_impaired) }
                if p.visionImpaired { tags.append(.vision_impaired) }
                
                let name = p.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Person" : p.name.trimmingCharacters(in: .whitespaces)
                store.dispatch(.addProfile(profileId: p.id, name: name, tags: tags, bedroom_room_id: defaultBedroom))
            }
            
            store.dispatch(.setHousehold(tenure: tenure, existingEquipment: []))
            
            self.seededHome = store.model
            // keep undoStack alive to avoid garbage collection? No need, it's just a testable side effect on the model store! But wait, UndoStack observes `onCommit`. In real usage, the `HomeModelStore` handles persistence. Let's just create an undo stack in the test, not here. Here we just rely on `onCommit`.
        } catch {
            print("Failed to initialize store: \(error)")
        }
    }
}
