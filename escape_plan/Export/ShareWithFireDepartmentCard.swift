//  ShareWithFireDepartmentCard.swift
//  escape_plan — Export module
//
//  S11.6: the headline entry point for "Share with your fire department" — a working
//  firefighter told this team that the best idea in the app is an opt-in path where a family
//  shares its own home information with its own department, and that stored layouts go stale
//  and departments cannot act on self-reported data. This card is built around both halves of
//  that: a one-tap share AND an honesty pass the resident cannot miss (consent every time,
//  a staleness line, a disclaimer that this is prevention, not a mid-fire tool).
//
//  SELF-CONTAINED BY DESIGN: this view takes everything it needs via its initializer so it
//  can be dropped into any parent (S11.5's HomeScreen wires it in at integration; this session
//  never touches HomeScreen.swift). It never reaches into a shared environment object for its
//  own state, only for what SwiftUI requires structurally.
//
//  No SceneKit, no route computation, no network — it calls the same offline
//  `EscapePlanExporter` the printable plan does. See `EscapePlanExporter`, `ConsentSheet`.

import SwiftUI

struct ShareWithFireDepartmentCard: View {
    let homeID: String
    private let exporter: EscapePlanExporter

    @State private var showingConsent = false
    @State private var isGenerating = false
    @State private var shareURLs: [URL]?
    @State private var generateError: String?

    init(homeID: String, store: HomeDocumentStore) {
        self.homeID = homeID
        self.exporter = EscapePlanExporter(store: store)
    }

    /// Test/preview seam — mirrors `ExportPlanSheet`'s init pattern.
    init(homeID: String, exporter: EscapePlanExporter) {
        self.homeID = homeID
        self.exporter = exporter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                DSIconBadge(systemImage: "flame.fill", fill: Theme.hazardInk)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share with your fire department")
                        .font(.headline)
                        .foregroundStyle(DS.ink)
                    Text("Offline PDF and JSON. Your choice, every time.")
                        .font(.footnote)
                        .foregroundStyle(DS.supporting)
                }
                Spacer(minLength: 0)
            }

            Text("Not for use in an emergency — this is a prevention and readiness snapshot, "
                 + "never a tool for firefighters to use mid-fire.")
                .font(.caption)
                .foregroundStyle(Theme.caution)

            if let generateError {
                Text(generateError)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }

            Button {
                showingConsent = true
            } label: {
                HStack {
                    Spacer(minLength: 0)
                    if isGenerating {
                        ProgressView()
                    } else {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Spacer(minLength: 0)
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(height: 48)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: DS.buttonRadius, style: .continuous))
            }
            .buttonStyle(DSPressStyle())
            .disabled(isGenerating)
            .accessibilityHint("Asks what to include, then opens the share sheet with a PDF and a JSON file for your department.")

            Button("Clear my snapshot") {
                ResponderSnapshotStore().clearSnapshots()
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.supporting)
            .accessibilityHint("Deletes any Responder Snapshot files saved on this device.")
        }
        .dsCard()
        .sheet(isPresented: $showingConsent) {
            ConsentSheet { decision in
                Task { await generate(consent: decision) }
            }
        }
        .background(ShareSheet(urls: $shareURLs))
    }

    private func generate(consent: SnapshotConsentDecision) async {
        isGenerating = true
        generateError = nil
        defer { isGenerating = false }
        do {
            let preview = try exporter.preview(homeID: homeID)
            try? await Task.sleep(for: .seconds(0.1))
            shareURLs = try exporter.writeResponderSnapshot(preview: preview, consent: consent)
        } catch {
            generateError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }
}
