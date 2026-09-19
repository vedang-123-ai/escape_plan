//
//  HazardHuntView.swift
//
//  The guided hazard hunt: a few yes/no questions per room that fill in what the scan cannot
//  see (RoomPlan has no bookcase, no water heater, no portable heater).
//
//  This view OWNS NO SAFETY LOGIC. Which questions get asked, in what order, and what each
//  answer writes to the model all live in `HazardHuntPlan` (EditorCore, pure, tested). The view
//  walks rooms, renders the current question, dispatches the answer's actions, and focuses the
//  camera. Keeping it that thin is why the questions are testable at all — see
//  docs/decisions.md, 2026-09-10.

import SwiftUI

struct HazardHuntView: View {
    let store: HomeModelStore
    @State private var isHunting = false
    @State private var currentRoomIndex = 0
    @State private var questionIndex = 0
    /// The plan for the room being hunted, derived ONCE on entry. Re-deriving per render would
    /// reshuffle the list under the user's thumb as their own answers change the model.
    @State private var plan: [HazardHuntQuestion] = []
    /// Answers so far, so a follow-up ("is it strapped?") can be skipped when its parent was a No.
    @State private var answers: [String: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isHunting {
                startButton
            } else {
                huntFlow
            }
        }
    }

    private var startButton: some View {
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

    private var currentQuestion: HazardHuntQuestion? {
        guard questionIndex < plan.count else { return nil }
        return plan[questionIndex]
    }

    // MARK: Flow

    private var huntFlow: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let ref = activeRoomRef {
                if let question = currentQuestion {
                    questionCard(question, in: ref)
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
                completionCard
            }
        }
    }

    private func questionCard(_ question: HazardHuntQuestion, in ref: RoomRef) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hazard Hunt: \(ref.room.name)")
                .font(.headline)
                .foregroundStyle(DS.ink)
            Text(question.text)
                .font(.body)
                .foregroundStyle(DS.bodyInk)
                .accessibilityIdentifier("house.hazardHunt.questionText")
            if let hint = question.placementHint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(DS.supporting)
                    .accessibilityIdentifier("house.hazardHunt.placementHint")
            }
            HStack(spacing: 12) {
                Button("Yes") { answer(question, yes: true) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .accessibilityIdentifier("house.hazardHunt.yes")

                Button("No") { answer(question, yes: false) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("house.hazardHunt.no")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.card, in: RoundedRectangle(cornerRadius: DS.cardRadius))
    }

    private var completionCard: some View {
        VStack(spacing: 16) {
            Text("Hazard Hunt Complete!")
                .font(.headline)
            Button("Done") { isHunting = false }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("house.hazardHunt.done")
        }
        .padding()
    }

    // MARK: Answering

    /// Dispatches the answer's actions in order, then selects the object the question was about
    /// so the user can drag it — or see the one the scan already placed for them.
    private func answer(_ question: HazardHuntQuestion, yes: Bool) {
        answers[question.id] = yes
        for action in (yes ? question.yes : question.no) {
            store.dispatch(action)
        }
        if yes {
            store.select(.object(objectId: question.objectId))
        }
        advance()
    }

    private func startHunt() {
        currentRoomIndex = 0
        answers = [:]
        isHunting = true
        enterRoom()
    }

    /// Skips any question whose parent was answered No — "is it strapped?" is meaningless once
    /// the user has said there is no water heater.
    private func advance() {
        var next = questionIndex + 1
        while next < plan.count, let parent = plan[next].requiresYesOf, answers[parent] != true {
            next += 1
        }
        if next < plan.count {
            questionIndex = next
        } else {
            nextRoom()
        }
    }

    private func nextRoom() {
        currentRoomIndex += 1
        if activeRoomRef != nil {
            enterRoom()
        } else {
            plan = []
        }
    }

    private func enterRoom() {
        guard let ref = activeRoomRef else { return }
        store.setActiveFloor(ref.floorId)
        store.select(.room(roomId: ref.room.id))
        plan = HazardHuntPlan.questions(
            for: ref.room,
            floorId: ref.floorId,
            objects: store.model.floors.first { $0.id == ref.floorId }?.objects ?? [],
            newObjectId: { _ in UUID().uuidString }
        )
        questionIndex = 0
        // A room can legitimately produce nothing to ask (a bathroom with no tall furniture).
        if plan.isEmpty { nextRoom() }
    }
}
