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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var messages: [AssistantMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var canRetry = false

    @State private var home: HomeModel?
    @State private var homeLoadError: String?
    @State private var loaded = false
    @FocusState private var composerFocused: Bool

    private let store = try? ConversationStore()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                groundingHeader
                messageList
            }
            // The composer lives in the bottom safe-area inset, not at the foot of the stack:
            // the keyboard shrinks the inset's host, so the field rides on the keyboard's top
            // edge on every device, and the list keeps its own room above it.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if let errorMessage {
                        errorBanner(errorMessage)
                    }
                    inputBar
                }
            }
            .dsPage()
            .navigationTitle("Assistant")
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { loadIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { persist() }
        }
    }

    // MARK: - Subviews

    /// Title row from the design: sparkle badge, "Assistant", which home it knows, new chat.
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.accent, in: Circle())
                .shadow(color: Theme.accent.opacity(0.3), radius: 5, y: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Assistant")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(DS.ink)
                    .accessibilityAddTraits(.isHeader)
                if let home {
                    Text("AI · knows \(home.name)")
                        .font(.footnote)
                        .foregroundStyle(DS.supporting)
                        .accessibilityLabel("Answers are about your home, \(home.name).")
                }
            }
            Spacer()
            Button {
                newChat()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 44, height: 44)
            }
            .disabled(messages.isEmpty && errorMessage == nil)
            .hapticTap()
            .accessibilityLabel("New chat")
            .accessibilityHint("Clears this conversation and starts a fresh one.")
        }
        .padding(.horizontal, DS.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    /// Only the failure case remains here; the grounded home is named in the header.
    @ViewBuilder
    private var groundingHeader: some View {
        if home == nil, let homeLoadError {
            Label(homeLoadError, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(Theme.warning)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.bar)
                .accessibilityLabel("The assistant has no home to answer about. \(homeLoadError)")
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
                            // Reduce Motion: a new message still appears (and still scrolls
                            // into view), it just fades rather than sliding up from below.
                            .transition(reduceMotion
                                        ? .opacity
                                        : .asymmetric(
                                            insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity))
                    }
                    if isSending {
                        typingIndicator.id("typing")
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, DS.pagePadding)
                .padding(.vertical, 12)
                .animation(reduceMotion ? .linear(duration: 0.15) : .spring(duration: 0.35),
                           value: messages.count)
                .animation(.easeInOut(duration: 0.2), value: isSending)
            }
            // Dragging the list down sheds the keyboard with the finger; a tap on empty list
            // space does it at once. Neither steals taps from the suggestion pills.
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { composerFocused = false }
            .onChange(of: composerFocused) { _, focused in
                // The keyboard would cover the newest message unless the list follows it up.
                guard focused, let last = messages.last else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    if reduceMotion {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    } else {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    // The scroll itself is jumped rather than animated under Reduce Motion —
                    // it still goes to the newest message, it just doesn't travel there.
                    if reduceMotion {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    } else {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .onChange(of: isSending) {
                if isSending {
                    if reduceMotion {
                        proxy.scrollTo("typing", anchor: .bottom)
                    } else {
                        withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                    }
                }
            }
        }
    }

    /// Prompts that hold for any home (the design's were tied to its demo house).
    private let suggestions = ["Why does my route go this way?", "What should I fix first?",
                               "How do I run a drill?", "Where should smoke alarms go?"]

    private var emptyState: some View {
        ZStack {
            AssistantGlow()
            VStack(spacing: 22) {
                Text("What would you like to know about your home?")
                    .font(.system(size: 26, weight: .bold))
                    .kerning(-0.3)
                    .foregroundStyle(DS.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(suggestions, id: \.self) { text in
                        Button {
                            draft = text
                            send()
                        } label: {
                            Text(text)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.accentText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 14)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(DS.card, in: Capsule())
                                .shadow(color: DS.shadowColor, radius: 9, y: 6)
                        }
                        .buttonStyle(DSPressStyle())
                        .disabled(home == nil)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.bottom, 30)
    }

    private var typingIndicator: some View {
        HStack {
            Group {
                if reduceMotion {
                    ProgressView()
                } else {
                    TypingDots()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(DS.card, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4,
                                                            bottomTrailingRadius: 18, topTrailingRadius: 18,
                                                            style: .continuous))
            .shadow(color: DS.shadowColor, radius: 9, y: 6)
            Spacer(minLength: 40)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Assistant is typing")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.caution)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("The assistant couldn't answer. \(message)")
            if canRetry {
                Button("Retry") { retry() }
                    .font(.footnote.bold())
                    .disabled(isSending)
                    .minimumTapTarget()
                    .accessibilityLabel("Retry")
                    .accessibilityHint("Sends your last question again.")
            }
        }
        .foregroundStyle(DS.bodyInk)
        .dsCard(radius: 12, padding: 12)
        .padding(.horizontal, DS.pagePadding)
        .padding(.bottom, 6)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask anything…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(DS.ink)
                .lineLimit(1...4)
                .padding(.leading, 12)
                .focused($composerFocused)
                .submitLabel(.send)
                .onSubmit { send() }
                .accessibilityLabel("Your question")
                .accessibilityHint("Ask anything about safety or your escape plan.")
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(canSend ? Theme.accent : Color(.systemGray3), in: Circle())
            }
            .buttonStyle(DSPressStyle())
            .disabled(!canSend)
            .accessibilityLabel("Send")
            .accessibilityHint(canSend
                               ? "Sends your question to the assistant."
                               : (home == nil
                                  ? "Unavailable until a home is loaded."
                                  : "Unavailable until you type a question."))
        }
        .padding(6)
        .background(DS.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: DS.shadowColor, radius: 9, y: 6)
        .padding(.horizontal, DS.pagePadding)
        .padding(.vertical, 10)
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
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 8) {
                Text(message.content)
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    // `Color.accentColor` behind white text measured 2.71:1 in dark mode — the
                    // app's own chat was its worst contrast failure. `Theme.bubbleUser` is a
                    // single deep green that carries white text at 5.04:1 on both pages.
                    .background(isUser ? AnyShapeStyle(Theme.bubbleUser) : AnyShapeStyle(DS.card),
                                in: UnevenRoundedRectangle(
                                    topLeadingRadius: 18,
                                    bottomLeadingRadius: isUser ? 18 : 4,
                                    bottomTrailingRadius: isUser ? 4 : 18,
                                    topTrailingRadius: 18,
                                    style: .continuous))
                    .foregroundStyle(isUser ? Color.white : DS.ink)
                    .shadow(color: isUser ? .clear : DS.shadowColor, radius: 9, y: 6)
                if !message.citations.isEmpty {
                    citationChips.padding(.leading, 4)
                }
            }
            if !isUser { Spacer(minLength: 40) }
        }
        // Who said it is conveyed by side + fill, neither of which a screen reader can see.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// "You asked: …" / "Assistant answered: … Sources: nfpa-escape-plan."
    private var spoken: String {
        var sentence = isUser ? "You asked: \(message.content)"
                              : "Assistant answered: \(message.content)"
        if !message.citations.isEmpty {
            sentence += " Sources: \(message.citations.joined(separator: ", "))."
        }
        return sentence
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
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DS.supporting)
                        Text(id)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DS.bodyInk)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(DS.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: Color(red: 27/255, green: 35/255, blue: 64/255).opacity(0.08), radius: 5, y: 3)
                }
            }
        }
        // Already spoken as part of the bubble's combined label; kept out of the tree so the
        // ids aren't read twice.
        .accessibilityHidden(true)
    }
}

// MARK: - Design touches

/// Soft green radial glow that breathes behind the empty state (the design's `epglow`).
/// Static under Reduce Motion — the presence stays, the movement goes.
private struct AssistantGlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swell = false

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.08), .clear],
                                 center: .center, startRadius: 0, endRadius: 170))
            .frame(width: 340, height: 340)
            .scaleEffect(swell ? 1.12 : 1.0)
            .opacity(swell ? 1.0 : 0.9)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { swell = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Three dots pulsing in sequence (the design's `epdot`).
private struct TypingDots: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color(.systemGray))
                    .frame(width: 8, height: 8)
                    .opacity(on ? 1 : 0.25)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.2), value: on)
            }
        }
        .onAppear { on = true }
    }
}

#Preview {
    AssistantScreen()
        .environment(APIClient())
}
