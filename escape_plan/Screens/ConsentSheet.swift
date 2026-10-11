import SwiftUI

/// Explicit, per-share consent for "Share with your fire department" (S11.6). This sheet is
/// shown every time a snapshot is about to be shared — not once, behind a settings toggle —
/// because the working firefighter this feature is built around said departments cannot act
/// on self-reported data unless the family chose, each time, to hand it over. Since S11.38
/// both entry points (Tasks and Settings) are the same `ShareWithFireDepartmentCard`; the
/// one-time "turn it on" gate Settings used to show was removed with its separate code path.
struct ConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let homeName: String
    let onAccept: (SnapshotConsentDecision) -> Void

    @State private var includeOccupantNames = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Share with your fire department")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(DS.ink)

                    Text("This creates an offline snapshot of \(homeName) for first responders — a floor plan, utility shutoffs, and a count of anyone who may need help evacuating. You choose when to send it; nothing leaves this device on its own.")
                        .font(.body)
                        .foregroundStyle(DS.bodyInk)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("What a share includes:")
                            .font(.headline)
                            .foregroundStyle(DS.ink)
                        bullet("Floor plan diagrams with exits marked")
                        bullet("Utility shutoff locations")
                        bullet("Occupant counts by room needing assistance (e.g. \"1 occupant — Bedroom 2\")")
                        bullet("Hazards the app's engine found, each with its source")
                        bullet("The date of your last scan, and a plain warning that this data is entered by you and unverified by any department")
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("What is EXCLUDED, unless you turn it on below:")
                            .font(.headline)
                            .foregroundStyle(Theme.caution)
                        bullet("Names of occupants")
                        bullet("Your address (unless you typed it into the home name)")
                        bullet("Device identifiers")
                    }

                    Toggle("Include occupant names", isOn: $includeOccupantNames)
                        .tint(Theme.accent)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.ink)
                        .accessibilityHint("Off by default. Turning this on adds the names of occupants needing assistance next to their room, instead of just a count.")

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Not for use in an emergency")
                            .font(.headline)
                            .foregroundStyle(DS.ink)
                        Text("This is a prevention and readiness snapshot, not a tool for firefighters to use mid-fire. Nothing is ever sent automatically — you pick the app (AirDrop, Messages, Files) each time you share.")
                            .font(.body)
                            .foregroundStyle(DS.bodyInk)
                    }

                    Button {
                        onAccept(SnapshotConsentDecision.acknowledgedNow(includeOccupantNames: includeOccupantNames))
                        dismiss()
                    } label: {
                        Text("Share")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.accent)
                            .cornerRadius(12)
                    }
                    .padding(.top, 16)

                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundStyle(Theme.supporting)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .padding(DS.pagePadding)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(DS.supporting)
            Text(text).foregroundStyle(DS.bodyInk)
        }
    }
}
