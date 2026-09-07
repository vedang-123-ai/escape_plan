import SwiftUI

struct OnboardingFlowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var state = OnboardingState()

    var onFinished: () -> Void

    var body: some View {
        NavigationStack {
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
        .onDisappear { state.cancelWork() }
    }

    // MARK: - Step 0: Welcome

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Escape Plan")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            
            Text("I'll ask a few questions about your household, then build you a personalized readiness checklist for fire, earthquake and severe weather.")
                .font(.title3)
                .foregroundStyle(Theme.supporting)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
            
            if let seedError = state.seedError {
                Label(seedError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }
            
            Button {
                state.seedIfNeeded()
                if state.seededHome != nil { state.step = .whoLivesHere }
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            
            Button("Skip for now") {
                state.seedIfNeeded()
                state.commitAndFinish()
                onFinished()
            }
            .font(.subheadline)
            .padding(.bottom)
            .minimumTapTarget()
        }
    }

    // MARK: - Step 1: Who lives here

    private var whoLivesHere: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Who lives here?")
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                    
                    Text("We use ages to customize the readiness plan — like adding child-assistance steps or elderly egress options. You don't need to provide exact birthdates.")
                        .foregroundStyle(Theme.supporting)
                    
                    ForEach($state.persons) { $person in
                        VStack(spacing: 12) {
                            TextField("Name (optional)", text: $person.name)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.name)
                            
                            TextField("Age (optional)", text: $person.age)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                        }
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    
                    Button {
                        state.persons.append(OnboardingState.Person())
                    } label: {
                        Label("Add another person", systemImage: "plus.circle.fill")
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            
            VStack(spacing: 12) {
                Button {
                    state.step = .needs
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Button("Skip this step") {
                    state.step = .needs
                }
                .font(.subheadline)
            }
            .padding()
            .background(.background)
        }
    }

    // MARK: - Step 2: Per-person needs

    private var needs: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Does anyone need extra help?")
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                    
                    Text("This helps us route away from stairs for wheelchairs, or suggest strobe alarms for the hearing impaired. Nothing here is required.")
                        .foregroundStyle(Theme.supporting)
                    
                    ForEach($state.persons) { $person in
                        let displayName = person.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Person" : person.name
                        
                        VStack(alignment: .leading, spacing: 16) {
                            Text(displayName).font(.headline)
                            
                            Toggle("Limited mobility", isOn: $person.mobilityLimited)
                            Toggle("Hearing impaired", isOn: $person.hearingImpaired)
                            Toggle("Vision impaired", isOn: $person.visionImpaired)
                        }
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            
            VStack(spacing: 12) {
                Button {
                    state.step = .rentOrOwn
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Button("Skip this step") {
                    state.step = .rentOrOwn
                }
                .font(.subheadline)
            }
            .padding()
            .background(.background)
        }
    }

    // MARK: - Step 3: Rent or own

    private var rentOrOwn: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Do you rent or own?")
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                    
                    Text("Some safety fixes — like bolting heavy furniture to wall studs for earthquake prep — need a landlord's permission. We'll adjust the checklist so it only suggests renter-friendly options if you rent.")
                        .foregroundStyle(Theme.supporting)
                    
                    HStack(spacing: 16) {
                        Button {
                            state.tenure = .rent
                        } label: {
                            VStack {
                                Image(systemName: "building.2")
                                    .font(.largeTitle)
                                    .padding(.bottom, 4)
                                Text("Rent")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(state.tenure == .rent ? AnyShapeStyle(Theme.accent.opacity(0.15)) : AnyShapeStyle(.regularMaterial), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(state.tenure == .rent ? Theme.accent : .clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Rent")
                        .accessibilityAddTraits(state.tenure == .rent ? .isSelected : [])
                        
                        Button {
                            state.tenure = .own
                        } label: {
                            VStack {
                                Image(systemName: "house")
                                    .font(.largeTitle)
                                    .padding(.bottom, 4)
                                Text("Own")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(state.tenure == .own ? AnyShapeStyle(Theme.accent.opacity(0.15)) : AnyShapeStyle(.regularMaterial), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(state.tenure == .own ? Theme.accent : .clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Own")
                        .accessibilityAddTraits(state.tenure == .own ? .isSelected : [])
                    }
                }
                .padding()
            }
            
            VStack(spacing: 12) {
                Button {
                    state.commitAndFinish()
                    onFinished()
                } label: {
                    Text("Finish")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Button("Skip this step") {
                    state.commitAndFinish()
                    onFinished()
                }
                .font(.subheadline)
            }
            .padding()
            .background(.background)
        }
    }
}
