import SwiftUI

struct ConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAccept: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Responder Snapshot")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(DS.ink)
                    
                    Text("This feature generates an offline snapshot of your home designed for first responders. It contains your floor plan, the location of utility shutoffs, and a count of vulnerable occupants by room.")
                        .font(.body)
                        .foregroundStyle(DS.bodyInk)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("What is included:")
                            .font(.headline)
                            .foregroundStyle(DS.ink)
                        bullet("Floor plan diagrams with exits marked")
                        bullet("Utility shutoff locations")
                        bullet("Anonymous occupant counts by room (e.g. \"1 occupant needing assistance\")")
                        bullet("Safety hazards (e.g. no safe room)")
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("What is EXCLUDED:")
                            .font(.headline)
                            .foregroundStyle(Theme.caution)
                        bullet("Names of occupants")
                        bullet("Your address (unless you typed it into the home name)")
                        bullet("Device identifiers")
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("No automatic transmission")
                            .font(.headline)
                            .foregroundStyle(DS.ink)
                        Text("Nothing is ever sent to a fire department automatically. You must manually share the generated file.")
                            .font(.body)
                            .foregroundStyle(DS.bodyInk)
                    }
                    
                    Button {
                        onAccept()
                        dismiss()
                    } label: {
                        Text("I Understand")
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
