import SwiftUI

/// Explicit, per-share consent for "Share with your fire department" (S11.6). This sheet is
/// shown every time a snapshot is about to be shared — not once, behind a settings toggle —
/// because the working firefighter this feature is built around said departments cannot act
/// on self-reported data unless the family chose, each time, to hand it over.
struct ConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let homeName: String
    let onAccept: (SnapshotConsentDecision) -> Void
    /// True ONLY for the one-time "turn the feature on" gate in Settings. Accepting there
    /// does NOT generate or share anything — it just reveals the "Share" action, which shows
    /// this same sheet again (with this `false`) before every actual share. Kept as one view
    /// rather than two so the two moments can never drift apart in wording, but the CTA and
    /// intro differ so accepting the gate is never mistaken for having shared something
    /// (swift-scenekit-reviewer, S11.6).
    var isEnablingOnly: Bool = false

    @State private var includeOccupantNames = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Share with your fire department")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(DS.ink)

                    Text(isEnablingOnly
                         ? "Turning this on adds a \"Share\" action to this screen. Nothing is generated or sent yet — every actual share asks again, right before it happens, and lets you choose what's included."
                         : "This creates an offline snapshot of \(homeName) for first responders — a floor plan, utility shutoffs, and a count of anyone who may need help evacuating. You choose when to send it; nothing leaves this device on its own.")
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

                    if !isEnablingOnly {
                        Toggle("Include occupant names", isOn: $includeOccupantNames)
                            .tint(Theme.accent)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DS.ink)
                            .accessibilityHint("Off by default. Turning this on adds the names of occupants needing assistance next to their room, instead of just a count.")
                    }

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
                        // "Turn On" here never claims a share happened — only the per-share
                        // sheet's button says "Share", and only that one actually shares.
                        Text(isEnablingOnly ? "Turn On" : "Share")
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
