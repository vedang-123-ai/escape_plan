//  OnboardingFlowView.swift
//  escape_plan
//
//  The household interview (S6.5), in the Claude Design language (2026-09-07): step dots, a
//  hero mark on the welcome step, `.title` titles (fixed 28pt until the 2026-09-25 audit), card-wrapped fields, one 56pt primary action
//  and a quiet "I'll do this later" under it. Every step still writes to `OnboardingState`
//  exactly as before — this pass changes how the interview looks, not what it captures.

import SwiftUI

struct OnboardingFlowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var state: OnboardingState

    var onFinished: () -> Void

    /// `documentStore` is the library's store (AUD-019). Passed in, not read from the
    /// environment: ContentView presents this cover outside its `.environmentObject(library)`.
    init(documentStore: HomeDocumentStore, onFinished: @escaping () -> Void) {
        _state = State(initialValue: OnboardingState(documentStore: documentStore,
                                                     homeMemory: ActiveHomeMemory()))
        self.onFinished = onFinished
    }

    private let steps: [OnboardingState.Step] = [.welcome, .whoLivesHere, .needs, .rentOrOwn]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepDots
                Group {
                    switch state.step {
                    case .welcome: welcome
                    case .whoLivesHere: whoLivesHere
                    case .needs: needs
                    case .rentOrOwn: rentOrOwn
                    case .done: EmptyView()
                    }
                }
                .animation(reduceMotion ? nil : .default, value: state.step)
            }
            .dsPage()
            .toolbar(.hidden, for: .navigationBar)
        }
        .onDisappear { state.cancelWork() }
    }

    // MARK: - Shared pieces

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(steps, id: \.self) { step in
                Circle()
                    .fill(step == state.step ? Theme.accent : Color(.systemGray4))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \((steps.firstIndex(of: state.step) ?? 0) + 1) of \(steps.count)")
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.title.bold())
            .kerning(-0.3)
            .foregroundStyle(DS.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func lede(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(DS.supporting)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Primary action plus the quiet escape hatch, pinned under the step's content.
    private func footer(primary: String, action: @escaping () -> Void,
                        later: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            DSPrimaryButton(title: primary, action: action)
            Button("I'll do this later", action: later)
                .hapticTap()
                .font(.subheadline)
                .foregroundStyle(DS.supporting)
                .frame(height: 44)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }

    // MARK: - Step 0: Welcome

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "house")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 96, height: 96)
                    .background(
                        LinearGradient(colors: [DS.accentFill, Theme.accent.opacity(0.28)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle())
                    .shadow(color: Theme.accent.opacity(0.16), radius: 13, y: 10)
                    .padding(.bottom, 6)
                    .accessibilityHidden(true)
                title("Let's map your home")
                    .multilineTextAlignment(.center)
                // Prevention and readiness lead; the escape route follows. Never a claim
                // that firefighters use this app (CLAUDE.md — "not a tool for firefighters
                // to use mid-fire"; the firefighter we talked to reacted best to prevention).
                Text("Map it once. We'll show cited prevention basics, a readiness checklist, and an escape route for every person who lives here.")
                    .font(.body)
                    .foregroundStyle(DS.supporting)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .padding(.horizontal, 28)
            Spacer()
            if let seedError = state.seedError {
                Label(seedError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .padding(.bottom, 12)
            }
            footer(primary: "Get started", action: {
                // Library state decides only whether a demo home is seeded. The interview always
                // runs: starter homes are seeded at launch, so "the library isn't empty" was true
                // on every fresh install and this used to skip straight past it.
                state.seedIfNeeded()
                state.step = .whoLivesHere
            }, later: {
                state.seedIfNeeded()
                if state.seededHome != nil { state.commitAndFinish() }
                onFinished()
            })
        }
    }

    // MARK: - Step 1: Who lives here

    private var whoLivesHere: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    title("Who lives here?")
                    lede("Routes are personal. Someone who sleeps upstairs and can't take stairs quickly needs a different way out. Ages help too — exact birthdays aren't needed.")
                    VStack(spacing: 8) {
                        ForEach($state.persons) { $person in
                            HStack(spacing: 14) {
                                Text(initial(for: person.name))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Theme.accentText)
                                    .frame(width: 34, height: 34)
                                    .background(DS.accentFill, in: Circle())
                                    .accessibilityHidden(true)
                                VStack(spacing: 6) {
                                    TextField("Name (optional)", text: $person.name)
                                        .font(.body.weight(.medium))
                                        .textContentType(.name)
                                    TextField("Age (optional)", text: $person.age)
                                        .font(.subheadline)
                                        .keyboardType(.numberPad)
                                }
                                .textFieldStyle(.plain)
                            }
                            .dsCard(padding: 16)
                        }
                        Button {
                            state.persons.append(OnboardingState.Person())
                        } label: {
                            Text("+ Add a person or pet")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accentText)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: DS.buttonRadius, style: .continuous)
                                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                                        .foregroundStyle(Color(.systemGray3)))
                        }
                        .buttonStyle(DSPressStyle())
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            footer(primary: "Continue", action: { state.step = .needs },
                   later: { state.step = .needs })
        }
    }

    private func initial(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1)).uppercased()
    }

    // MARK: - Step 2: Per-person needs

    private var needs: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    title("Does anyone need extra help?")
                    lede("This routes away from stairs for a wheelchair, or suggests strobe alarms for someone hard of hearing. Nothing here is required.")
                    VStack(spacing: 10) {
                        ForEach($state.persons) { $person in
                            let displayName = person.name.trimmingCharacters(in: .whitespaces).isEmpty
                                ? "Person" : person.name
                            VStack(alignment: .leading, spacing: 12) {
                                Text(displayName)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(DS.ink)
                                Toggle("Limited mobility", isOn: $person.mobilityLimited)
                                Toggle("Hearing impaired", isOn: $person.hearingImpaired)
                                Toggle("Vision impaired", isOn: $person.visionImpaired)
                            }
                            .onChange(of: [person.mobilityLimited, person.hearingImpaired,
                                           person.visionImpaired]) { Haptics.selection() }
                            .tint(Theme.accent)
                            .foregroundStyle(DS.bodyInk)
                            .dsCard(padding: 16)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            footer(primary: "Continue", action: { state.step = .rentOrOwn },
                   later: { state.step = .rentOrOwn })
        }
    }

    // MARK: - Step 3: Rent or own

    private var rentOrOwn: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    title("Do you rent or own?")
                    lede("Some fixes — like bolting heavy furniture to studs for earthquakes — need a landlord's permission. If you rent, the checklist only suggests renter-friendly options.")
                    HStack(spacing: 12) {
                        tenureCard(isSelected: state.tenure == .rent, label: "Rent",
                                   symbol: "building.2") { state.tenure = .rent }
                        tenureCard(isSelected: state.tenure == .own, label: "Own",
                                   symbol: "house") { state.tenure = .own }
                    }
                    .padding(.top, 8)
                    if let commitError = state.commitError {
                        Label(commitError, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            footer(primary: "Finish", action: {
                // Close only over a household that was actually saved; on failure the reason
                // stays on screen and "I'll do this later" still leaves.
                if state.commitAndFinish() { onFinished() }
            }, later: {
                // Leaving is the user's call, so a failed save does not hold them here; what
                // they did answer is still written if it can be.
                _ = state.commitAndFinish()
                onFinished()
            })
        }
    }

    private func tenureCard(isSelected selected: Bool, label: String, symbol: String,
                            select: @escaping () -> Void) -> some View {
        Button(action: select) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .foregroundStyle(selected ? Theme.accent : DS.bodyInk)
                    .accessibilityHidden(true)  // the label says it; never the symbol's name
                Text(label)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2))
            .shadow(color: DS.shadowColor, radius: 9, y: 6)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
