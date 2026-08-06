//  ExportPlanSheet.swift
//  escape_plan — Export module
//
//  The one screen of the export flow: capture the outside meeting place, say honestly what
//  the printout will and won't contain, render the PDF, hand it to the share sheet.
//
//  The meeting place is asked for HERE rather than stored on the home because it is not a
//  schema field and must not become one — see `MeetingPointStore`. The last answer is
//  remembered per home, so this is a confirm-and-print step, not a re-type-it-every-time one.
//
//  Nothing on this screen touches the network. See `EscapePlanExporter`.

import SwiftUI

/// Identifiable wrapper so a home id can drive `.sheet(item:)`.
struct ExportTarget: Identifiable, Hashable {
    let id: String
}

struct ExportPlanSheet: View {
    let homeID: String
    private let exporter: EscapePlanExporter

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var preview: EscapePlanExporter.Preview?
    @State private var meetingPoint = ""
    @State private var loadError: String?
    @State private var exportError: String?
    @State private var isGenerating = false
    @State private var shareURL: URL?

    init(homeID: String, store: HomeDocumentStore) {
        self.homeID = homeID
        self.exporter = EscapePlanExporter(store: store)
    }

    /// Test/preview seam.
    init(homeID: String, exporter: EscapePlanExporter) {
        self.homeID = homeID
        self.exporter = exporter
    }

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView {
                        Label("Can't print this home", systemImage: "doc.badge.ellipsis")
                    } description: {
                        Text(loadError)
                    }
                } else if let preview {
                    form(preview)
                } else {
                    ProgressView("Reading your home…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Printable Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .minimumTapTarget()
                        .accessibilityLabel("Done")
                        .accessibilityHint("Closes the printable plan without exporting.")
                        .accessibilityIdentifier("export.done")
                }
            }
        }
        .background(ShareSheet(url: $shareURL))
        .task { load() }
        .alert("Couldn't create the PDF",
               isPresented: Binding(get: { exportError != nil },
                                    set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    @ViewBuilder
    private func form(_ preview: EscapePlanExporter.Preview) -> some View {
        Form {
            Section {
                TextField("The big oak across the street", text: $meetingPoint, axis: .vertical)
                    // Grows to five lines at the accessibility text sizes: a three-line cap
                    // that fits "the big oak across the street" at default type scrolls the
                    // user's own words out of sight at AX3.
                    .lineLimit(dynamicTypeSize >= .accessibility1 ? 1...5 : 1...3)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel("Outside meeting place")
                    .accessibilityValue(meetingPoint.isEmpty ? "Empty" : meetingPoint)
                    .accessibilityHint(
                        "The place everyone gathers once they are out. It is printed in large "
                        + "type on every page and saved for next time.")
                    .accessibilityIdentifier("export.meetingPoint")
            } header: {
                Text("Outside meeting place")
            } footer: {
                Text("Printed on every page. Leave it blank and the plan prints a line to write "
                     + "it in by hand.")
            }

            Section("What gets printed") {
                summaryRow(icon: "doc.on.doc",
                           title: "\(preview.floorCount) page\(preview.floorCount == 1 ? "" : "s")",
                           detail: "One per floor, with the plan drawn from your own model.")
                summaryRow(icon: preview.hasRoutes ? "point.topleft.down.to.point.bottomright.curvepath"
                                                   : "wifi.slash",
                           title: preview.hasRoutes ? "Escape routes included" : "No routes available",
                           detail: routesDetail(preview))
                summaryRow(icon: "person.2",
                           title: "\(preview.peopleCount) "
                                + "\(preview.peopleCount == 1 ? "person" : "people")",
                           detail: preview.peopleCount == 0
                               ? "Add profiles in the app to get step-by-step directions per person."
                               : "Each gets their route written out as numbered steps.")
                summaryRow(icon: "printer",
                           title: "Black-and-white safe",
                           detail: "Solid line is the primary route, dashed is the backup — no "
                                 + "colour needed to tell them apart.")
            }

            Section {
                Button {
                    generate(preview)
                } label: {
                    HStack {
                        Spacer(minLength: 0)
                        if isGenerating {
                            ProgressView()
                        } else {
                            Label("Create PDF", systemImage: "square.and.arrow.up")
                        }
                        Spacer(minLength: 0)
                    }
                }
                .disabled(isGenerating)
                .minimumTapTarget()
                .accessibilityLabel(isGenerating ? "Creating PDF" : "Create PDF")
                .accessibilityHint("Builds the printable escape plan, then opens the share sheet "
                                   + "so you can print it, save it to Files, or AirDrop it.")
                .accessibilityIdentifier("export.createPDF")
            }
        }
    }

    private func summaryRow(icon: String, title: String, detail: String) -> some View {
        // Icon + two lines that wrap instead of truncating — this whole section has to stay
        // readable at the largest accessibility text sizes.
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.supporting)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(Theme.supporting)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func routesDetail(_ preview: EscapePlanExporter.Preview) -> String {
        if let computed = preview.routesComputedAt {
            return "Computed by the routing engine on "
                + computed.formatted(date: .abbreviated, time: .shortened) + "."
        }
        if preview.hasRoutes {
            return "Computed by the routing engine."
        }
        return "No routes have been computed on this device yet. The plan still prints, and says "
             + "plainly that the routes are missing — it never invents one."
    }

    // MARK: - Actions

    private func load() {
        do {
            let preview = try exporter.preview(homeID: homeID)
            self.preview = preview
            self.meetingPoint = preview.meetingPoint
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func generate(_ preview: EscapePlanExporter.Preview) {
        let trimmed = meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        exporter.meetingPoints.setMeetingPoint(trimmed, forHomeID: homeID)
        isGenerating = true
        // UIGraphicsPDFRenderer and attributed-string drawing are UIKit; keep them on the
        // main actor. These documents are a handful of pages of vector output.
        do {
            shareURL = try exporter.writePDF(preview: preview, meetingPoint: trimmed)
        } catch {
            exportError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
        isGenerating = false
    }
}
