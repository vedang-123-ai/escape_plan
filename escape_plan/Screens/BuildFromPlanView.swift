//  BuildFromPlanView.swift
//  escape_plan
//
//  Revamp C2: "describe or import a plan" — the no-LiDAR intake. The user types a
//  description and/or attaches a floor-plan image (photo or PDF page, rasterized here with
//  PDFKit — the backend only ever sees PNG/JPEG). POST /build returns a DRAFT home whose
//  every element is source=ai_plan; we save it and hand it to the editor, where the review
//  gate (HouseScreen) blocks route fetching until the user confirms the draft.

import PDFKit
import PhotosUI
import SwiftUI

struct BuildFromPlanView: View {
    /// Called with the saved home's id after a successful build.
    var onBuilt: (String) -> Void

    @Environment(APIClient.self) private var apiClient
    @Environment(\.dismiss) private var dismiss
    /// Reaches this sheet from HomeScreen's environment; the draft is saved through its store.
    @EnvironmentObject private var library: HomeLibrary

    @State private var descriptionText = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var imageLabel: String?
    @State private var showingPDFImporter = false
    @State private var isBuilding = false
    /// Local, non-backend problems: an unreadable PDF, or a draft the builder returned but
    /// couldn't validate. These are not transport failures and must not borrow their wording.
    @State private var errorMessage: String?
    /// Backend failures go through the one classifier. This file used to carry its own
    /// `statusCode == 502 / == 401` ladder, which disagreed with every other screen and — the
    /// real cost — offered the same affordances for "retry may work" and "an operator must act".
    @State private var buildFailure: BackendFailure?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "e.g. Single-story 2-bed bungalow, front door into the living room…",
                        text: $descriptionText,
                        axis: .vertical
                    )
                    .lineLimit(4...10)
                    .accessibilityLabel("Describe your home")
                    .accessibilityHint("Say how many floors and rooms there are, and where the "
                                       + "outside doors are.")
                } header: {
                    Text("Describe your home").accessibilityAddTraits(.isHeader)
                }
                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose a photo", systemImage: "photo")
                    }
                    .accessibilityLabel("Choose a photo")
                    .accessibilityHint("Attaches a photo of a floor plan from your library.")
                    Button {
                        showingPDFImporter = true
                    } label: {
                        Label("Choose a PDF", systemImage: "doc")
                    }
                    .accessibilityHint("Attaches the first page of a floor-plan PDF.")
                    if let attachedLabel = imageLabel {
                        HStack {
                            Text(attachedLabel).font(.caption).foregroundStyle(Theme.supporting)
                            Spacer()
                            Button("Remove") {
                                imageData = nil
                                imageLabel = nil
                                photoItem = nil
                            }
                            .font(.caption)
                            .minimumTapTarget()
                            .accessibilityLabel("Remove attachment")
                            .accessibilityHint("Detaches the floor plan you attached.")
                        }
                        .accessibilityElement(children: .contain)
                    }
                } header: {
                    Text("Or attach a floor plan").accessibilityAddTraits(.isHeader)
                }
                Section {
                    Button {
                        buildHome()
                    } label: {
                        if isBuilding {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Building your draft… this can take a minute.")
                            }
                        } else {
                            Label("Build draft home", systemImage: "wand.and.stars")
                        }
                    }
                    .disabled(isBuilding || (trimmedDescription == nil && imageData == nil))
                    .accessibilityLabel(isBuilding ? "Building your draft home"
                                                   : "Build draft home")
                    .accessibilityValue(isBuilding ? "In progress, this can take a minute" : "")
                    .accessibilityHint(isBuilding
                                       ? ""
                                       : (trimmedDescription == nil && imageData == nil
                                          ? "Unavailable until you describe your home or attach "
                                            + "a floor plan."
                                          : "Drafts a 3D model you'll review before any escape "
                                            + "route is computed."))
                    .accessibilityAddTraits(isBuilding ? [.updatesFrequently] : [])
                } footer: {
                    Text("""
                    The AI drafts a 3D model of your home for you to review. Nothing is \
                    trusted until you confirm it in the editor — and escape routes are only \
                    computed on the reviewed model, never on the raw draft.
                    """)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Couldn't build your home. \(errorMessage)")
                    }
                }
                if let buildFailure {
                    Section {
                        BackendFailureBanner(
                            failure: buildFailure,
                            retry: buildFailure.isRetryable ? { buildHome() } : nil
                        )
                        .accessibilityIdentifier("build.failure")
                        if buildFailure.isOfflineFlavoured {
                            OfflineCapabilityNote()
                        }
                    }
                }
            }
            .navigationTitle("Import a plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isBuilding)
                        .accessibilityHint(isBuilding
                                           ? "Unavailable while your draft is being built."
                                           : "Closes without building anything.")
                }
            }
        }
        .interactiveDismissDisabled(isBuilding)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    imageData = data
                    imageLabel = "Photo attached (\(data.count / 1024) KB)"
                }
            }
        }
        .fileImporter(isPresented: $showingPDFImporter,
                      allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result {
                importPDF(url)
            }
        }
    }

    private var trimmedDescription: String? {
        let text = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// First page of the PDF → PNG. Client-side on purpose: the backend accepts only
    /// PNG/JPEG and gains no PDF dependency.
    private func importPDF(_ url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else {
            errorMessage = "Couldn't read that PDF."
            return
        }
        let bounds = page.bounds(for: .mediaBox)
        // ~150 dpi equivalent: plenty for wall lines without a huge upload.
        let scale = min(2.0, 3000 / max(bounds.width, bounds.height))
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        imageData = image.pngData()
        imageLabel = "PDF page 1 attached"
    }

    private func buildHome() {
        errorMessage = nil
        buildFailure = nil
        isBuilding = true
        Task {
            defer { isBuilding = false }
            do {
                let response = try await apiClient.build(
                    description: trimmedDescription,
                    imageData: imageData
                )
                guard let home = response.home else {
                    errorMessage = response.issues.isEmpty
                        ? "The builder couldn't construct a home from that input — try adding more detail."
                        : "The draft didn't validate: " + response.issues.prefix(3).joined(separator: "; ")
                    return
                }
                try library.store.save(model: home)
                dismiss()
                onBuilt(home.home_id)
            } catch is CancellationError {
            } catch {
                // One classifier for every status: 502 gets no Retry and says the editor still
                // works, 503 gets one, 401 points at Settings, offline reads as a state.
                buildFailure = BackendFailure(error, while: .houseBuilder)
            }
        }
    }
}

#Preview {
    BuildFromPlanView(onBuilt: { _ in })
        .environment(APIClient())
        .environmentObject(HomeLibrary(store: HomeDocumentStore.launchStore().store))
}
