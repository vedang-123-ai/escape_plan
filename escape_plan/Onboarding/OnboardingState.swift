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
    /// True when the library already had a home, so no demo copy was seeded. It decides only
    /// THAT — the interview still runs and writes to the active home (audit 2026-09-25: the
    /// app seeds starter homes at launch, so this was true on every fresh install and "Get
    /// started" used to skip the whole interview).
    private(set) var hasExistingLibrary = false
    /// Why the household could not be saved, if it could not. Shown on the last step; the
    /// flow does not close over a failed write.
    private(set) var commitError: String?
    /// The home the household was written to, once `commitAndFinish()` has succeeded.
    private(set) var committedHomeID: String?
    /// The library's store (AUD-019). Required: a default of its own would write to Documents
    /// while the app runs on its temporary fallback store.
    private let documentStore: HomeDocumentStore
    /// The app's remembered active home (S53-2), so the answers land on the home `ReadinessStore`
    /// shows. nil in tests: then the demo home, else the first, exactly as `ReadinessStore` picks.
    private let homeMemory: ActiveHomeMemory?
    private let demoHomeID: String?

    init(documentStore: HomeDocumentStore, homeMemory: ActiveHomeMemory? = nil,
         demoHomeID: String? = FixtureSeeder.demoHomeID) {
        self.documentStore = documentStore
        self.homeMemory = homeMemory
        self.demoHomeID = demoHomeID
    }

    /// Seeds the demo home into an EMPTY library. With homes already present it seeds nothing
    /// and that is not an error.
    func seedIfNeeded() {
        guard seededHome == nil else { return }
        do {
            seededHome = try FixtureSeeder.seedDemoHome(into: store())
            hasExistingLibrary = seededHome == nil
            seedError = nil
        } catch {
            seedError = "Couldn't create the demo home: \(error.localizedDescription)"
        }
    }

    func cancelWork() {
        // No longer running /analyze in background during onboarding.
    }

    /// The home the interview's answers belong to: the demo copy if onboarding just seeded one,
    /// otherwise the home `ReadinessStore` makes active (`ActiveHomeMemory.choose`: remembered,
    /// else the demo home Two-Story House, else the first). On a fresh install that is Two-Story
    /// House, so the household shows on the home the app opens on.
    private func targetHome() throws -> HomeModel? {
        if let seededHome { return seededHome }
        let documentStore = store()
        guard let id = ActiveHomeMemory.choose(remembered: homeMemory?.remembered,
                                               available: documentStore.list().map(\.id),
                                               demoHomeID: demoHomeID) else { return nil }
        return try documentStore.load(homeID: id, as: HomeModel.self)
    }

    /// Writes the household (profiles and tenure) to the active home through `HomeModelStore`,
    /// the only path that mutates a model. Returns false, with `commitError` set, if nothing
    /// could be written — every dispatch outcome and the save itself are checked, where they
    /// used to be discarded and printed.
    @discardableResult
    func commitAndFinish() -> Bool {
        commitError = nil
        let home: HomeModel
        do {
            guard let target = try targetHome() else {
                commitError = "There's no home to save your household to yet. Add one from the Home tab."
                return false
            }
            home = target
        } catch {
            commitError = "Couldn't open your home to save your household: \(error.localizedDescription)"
            return false
        }

        let ordered = home.floors.sorted { $0.level < $1.level }
        let defaultBedroom = ordered.flatMap(\.rooms).first(where: { $0.type == .bedroom })?.id
            ?? ordered.first?.rooms.first?.id ?? ""

        do {
            let documentStore = store()
            let store = try HomeModelStore(model: home)

            var saveError: Error?
            store.onCommit = { commit in
                do {
                    try documentStore.save(model: commit.after)
                } catch {
                    saveError = error
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

                let trimmed = p.name.trimmingCharacters(in: .whitespaces)
                let name = trimmed.isEmpty ? "Person" : trimmed
                let outcome = store.dispatch(.addProfile(profileId: p.id, name: name, tags: tags,
                                                         bedroom_room_id: defaultBedroom))
                guard outcome.didApply else {
                    commitError = "Couldn't add \(name) to your home. Try again, or add them later in Profiles."
                    return false
                }
            }

            let outcome = store.dispatch(.setHousehold(tenure: tenure, existingEquipment: []))
            guard outcome.didApply else {
                commitError = "Couldn't save whether you rent or own. Try again."
                return false
            }
            if let saveError {
                commitError = "Couldn't save your household: \(saveError.localizedDescription)"
                return false
            }

            if seededHome != nil { seededHome = store.model }
            committedHomeID = home.home_id
            return true
        } catch {
            commitError = "Couldn't save your household: \(error.localizedDescription)"
            return false
        }
    }

    private func store() -> HomeDocumentStore {
        documentStore
    }
}
