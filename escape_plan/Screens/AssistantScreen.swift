//  AssistantScreen.swift
//  escape_plan
//
//  S3.3 grounded chat over the backend /chat endpoint. Routing is never computed here —
//  the deterministic backend engine owns that; this screen only ever talks to the backend,
//  and the backend's replies are grounded in the FEMA/NFPA/Red Cross corpus with inline
//  [cite: source-id] tags, which are rendered exactly as returned.
//
//  The server is stateless: every send resends the full history (ending with a user
//  message). The thread is persisted locally after every appended message, so it survives
//  backgrounding and force-quit.

import SwiftUI

struct AssistantScreen: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(\.scenePhase) private var scenePhase

    @State private var messages: [AssistantMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var canRetry = false

    @State private var home: HomeModel?
    @State private var homeLoadError: String?
    @State private var loaded = false

    private let store = try? ConversationStore()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                groundingHeader
                messageList
                if let errorMessage {
                    errorBanner(errorMessage)
                }
                inputBar
            }
            .navigationTitle("Assistant")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newChat()
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                    .disabled(messages.isEmpty && errorMessage == nil)
                }
            }
        }
        .task { loadIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { persist() }
        }
    }

    // MARK: - Subviews

    /// Which home the chat is grounded in — the backend requires a full HomeModel per turn.
    @ViewBuilder
    private var groundingHeader: some View {
        if let home {
            Label("Grounded in \(home.name)", systemImage: "house")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.bar)
        } else if let homeLoadError {
            Label(homeLoadError, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.bar)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if messages.isEmpty && !isSending {
                        emptyState
                    }
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                    if isSending {
                        typingIndicator.id("typing")
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .animation(.spring(duration: 0.35), value: messages.count)
                .animation(.easeInOut(duration: 0.2), value: isSending)
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: isSending) {
                if isSending {
                    withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Ask about your escape plan", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Ask anything about your family's escape plan — why a route goes the way it "
                 + "does, what to practice, what to fix first. Answers come from FEMA, NFPA, "
                 + "and Red Cross guidance, with sources shown.")
        }
        .padding(.top, 40)
    }

    private var typingIndicator: some View {
        HStack {
            ProgressView()
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Spacer(minLength: 40)
        }
        .accessibilityLabel("Assistant is typing")
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            if canRetry {
                Button("Retry") { retry() }
                    .font(.footnote.bold())
                    .disabled(isSending)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about fire safety in your home…", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit { send() }
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSending
            && home != nil
    }

    // MARK: - Actions

    /// Loads the persisted thread and the home the chat is grounded in: the most recently
    /// modified saved home, falling back to the bundled twostory fixture on a fresh install.
    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        if let document = store?.load() {
            messages = document.messages
        }

        do {
            let documentStore = try HomeDocumentStore()
            if let newest = documentStore.list().first {
                home = try documentStore.load(homeID: newest.id, as: HomeModel.self)
            } else {
                home = try FixtureLoader.load(.twostory)
            }
        } catch {
            homeLoadError = "No home available to ground the chat — save one on the Home tab."
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, home != nil, !isSending else { return }
        draft = ""
        messages.append(AssistantMessage(role: .user, content: text))
        persist()
        deliverPendingUserMessage()
    }

    /// Re-sends the current history (which still ends with the user's message) after a failure.
    private func retry() {
        guard messages.last?.role == .user else { return }
        deliverPendingUserMessage()
    }

    /// Calls /chat with the full history. The user's message is already in the thread and
    /// stays there on failure; the error banner offers Retry instead of dropping it.
    private func deliverPendingUserMessage() {
        guard let home else { return }
        isSending = true
        errorMessage = nil
        canRetry = false
        let history = messages.map(\.wireMessage)

        Task {
            do {
                let response = try await apiClient.chat(home: home, messages: history)
                messages.append(
                    AssistantMessage(role: .assistant,
                                     content: response.reply,
                                     citations: response.citations)
                )
                persist()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "The assistant couldn't answer — check your connection and try again."
                canRetry = true
                Haptics.warning()
            }
            isSending = false
        }
    }

    private func newChat() {
        messages = []
        errorMessage = nil
        canRetry = false
        try? store?.clear()
    }

    private func persist() {
        guard let store else { return }
        try? store.save(ConversationDocument(homeID: home?.home_id, messages: messages))
    }
}

// MARK: - Message bubble

/// One turn. Assistant text is rendered verbatim — inline `[cite: source-id]` tags stay
/// visible exactly as the backend returned them (grounding is the feature, not noise) —
/// with the server's citation id list echoed as chips underneath.
private struct MessageBubble: View {
    let message: AssistantMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                Text(message.content)
                    .textSelection(.enabled)
                if !message.citations.isEmpty {
                    citationChips
                }
            }
            .padding(12)
            .background(isUser ? Color.accentColor : Color(.secondarySystemBackground))
            .foregroundStyle(isUser ? Color.white : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            if !isUser { Spacer(minLength: 40) }
        }
    }

    private var citationChips: some View {
        FlowLayoutish(items: message.citations)
    }
}

/// Compact citation-id chips. A simple wrapping HStack substitute — citation lists are
/// short (a handful of ids), so a scrolling row is sufficient and avoids a Layout impl.
private struct FlowLayoutish: View {
    let items: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { id in
                    Text(id)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Capsule())
                }
            }
        }
        .accessibilityLabel("Citations: \(items.joined(separator: ", "))")
    }
}

#Preview {
    AssistantScreen()
        .environment(APIClient())
}
