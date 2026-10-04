//  AssistantScreen.swift
//  escape_plan
//
//  S3.3 grounded chat over the backend /chat endpoint. Routing is never computed here —
//  the deterministic backend engine owns that; this screen only ever talks to the backend,
//  and the backend's replies are grounded in the FEMA/NFPA/Red Cross corpus with inline
//  [cite: source-id] tags, which are rendered exactly as returned.
//
//  The server is stateless: every send resends the history (ending with a user message), trimmed
//  to the most recent turns within the server's caps (`ChatHistory`, S11.45); the whole thread
//  stays on screen. The thread is persisted locally after every appended message, so it survives
//  backgrounding and force-quit, and a save that fails is shown, not swallowed (AUD-049).
//
//  Grounding (audit 2026-09-25): the chat is about the ACTIVE home — `ReadinessStore.activeHome`,
//  the one Home, Tasks and House show — and follows it when it changes. It used to load the most
//  recently modified home once and never again, so it could answer about a different house from
//  the one on screen. Each home keeps its own thread (S11.45, AUD-033): switching homes swaps
//  threads instead of overwriting one.

import SwiftUI

struct AssistantScreen: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(ReadinessStore.self) private var readiness
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var messages: [AssistantMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    /// Classified by the shared `BackendFailure`, so the assistant's 401/429/502/503 read
    /// exactly as they do on every other screen, and Retry appears only when it can help.
    @State private var failure: BackendFailure?
    /// The home whose thread `messages` holds, so coming back to the tab does not re-read the
    /// file over a thread that could not be saved.
    @State private var loadedHomeID: String?
    /// Set when this home's thread could not be saved or cleared; cleared by the next success.
    @State private var historyProblem: String?
    /// Set when this home's saved thread could not be opened (it is kept aside, not lost).
    @State private var loadNotice: String?
    /// A home whose thread file is still on disk but could not be read. Nothing is saved or
    /// cleared for it until a later load succeeds, so the unread file is never written over.
    @State private var blockedHomeID: String?

    @FocusState private var composerFocused: Bool

    /// nil when Documents is unreachable. The chat still works; it just cannot be kept, and the
    /// screen says so rather than failing silently.
    private let store = try? ConversationStore()

    /// The home the chat is grounded in: the app's active home.
    private var home: HomeModel? { readiness.activeHome }

    /// Why there is no home to ground in, when there is none (nil while it is still loading).
    private var homeLoadError: String? {
        guard home == nil else { return nil }
        if readiness.activeHomeID == nil {
            return "No home yet — add one on the Home tab and the assistant will know it."
        }
        if let failure = readiness.scoreFailure, failure.kind == .localData {
            return failure.message
        }
        return nil
    }

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
                    if let failure {
                        BackendFailureBanner(failure: failure,
                                             retry: failure.isRetryable ? { retry() } : nil)
                            .padding(.horizontal, DS.pagePadding)
                            .padding(.bottom, 6)
                    }
                    if let note = historyNote {
                        Label(note, systemImage: "externaldrive.badge.xmark")
                            .font(.caption)
                            .foregroundStyle(DS.supporting)
                            .padding(.horizontal, DS.pagePadding)
                    }
                    if omittedTurns > 0 {
                        Text("Older messages stay here but aren't sent with new questions.")
                            .font(.caption)
                            .foregroundStyle(DS.supporting)
                            .padding(.horizontal, DS.pagePadding)
                    }
                    inputBar
                }
            }
            .dsPage()
            .navigationTitle("Assistant")
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { loadThread() }
        // Switching homes anywhere in the app switches what the assistant is about.
        .onChange(of: readiness.activeHomeID) { loadThread(homeChanged: true) }
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
            // Not while a reply is on its way: it would land at the top of the new thread.
            .disabled((messages.isEmpty && failure == nil) || isSending)
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
                    // Dynamic Type (audit 2026-09-25): was a fixed 26 pt.
                    .font(.title2.bold())
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

    /// The screen's one "history can't be saved" line: no store at all, a failed save or clear,
    /// or a saved thread that could not be opened.
    private var historyNote: String? {
        if store == nil { return "Chat history can't be saved on this device." }
        return historyProblem ?? loadNotice
    }

    /// How many earlier turns the next send leaves out (the quiet line above the composer).
    private var omittedTurns: Int {
        ChatHistory.trimmed(messages.map(\.wireMessage)).omittedCount
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSending
            && home != nil
    }

    // MARK: - Actions

    /// Shows the saved thread if it was about the active home; otherwise starts a fresh one.
    /// Called on appear (every tab switch back here, so it must be cheap and must not eat a
    /// half-typed question) and whenever the active home changes.
    private func loadThread(homeChanged: Bool = false) {
        let homeID = readiness.activeHomeID
        if homeChanged {
            failure = nil
            draft = ""
            historyProblem = nil
            loadNotice = nil
        } else if loadedHomeID != nil, loadedHomeID == homeID, blockedHomeID != homeID {
            return  // already showing this home's thread, saved or not
        }
        loadedHomeID = homeID
        messages = []
        guard let store else { return }
        var notices: [String] = []
        do {
            // The pre-S11.45 single file goes to its own home first (one existence check after).
            if case .keptAside = try store.migrateLegacyConversation() {
                notices.append("An earlier chat couldn't be matched to a home, so it was kept aside.")
            }
        } catch {
            notices.append("An earlier chat couldn't be moved to its home. It is still on this iPhone.")
        }
        do {
            messages = try store.load(forHomeID: homeID)?.messages ?? []
            blockedHomeID = nil
        } catch let unreadable as UnreadableConversation {
            blockedHomeID = nil  // the file was moved aside, so saving can no longer overwrite it
            notices.append(unreadable.errorDescription ?? "")
        } catch {
            // The file is still there, unread: block saving so it is not replaced by this new thread.
            blockedHomeID = homeID
            notices.append("This home's earlier chat couldn't be opened, so new messages won't be saved until it can be.")
        }
        loadNotice = notices.isEmpty ? nil : notices.joined(separator: " ")
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
        failure = nil
        // The most recent turns that fit the server's caps; the full thread stays on screen.
        let history = ChatHistory.trimmed(messages.map(\.wireMessage)).messages
        let askedAbout = home.home_id

        Task {
            do {
                let response = try await apiClient.chat(home: home, messages: history)
                // The user switched homes while this was in flight: the answer is about a home
                // no longer on screen, so it does not join the new home's thread.
                guard readiness.activeHomeID == askedAbout else { isSending = false; return }
                messages.append(
                    AssistantMessage(role: .assistant,
                                     content: response.reply,
                                     citations: response.citations)
                )
                persist(homeID: askedAbout)
            } catch {
                if readiness.activeHomeID == askedAbout, !BackendFailure.isCancellation(error) {
                    failure = BackendFailure(error, while: .assistant)
                    Haptics.warning()
                }
            }
            isSending = false
        }
    }

    private func newChat() {
        messages = []
        failure = nil
        // While blocked the notice stays: it is why this new chat is not being saved.
        guard let store, let homeID = loadedHomeID, blockedHomeID != homeID else { return }
        loadNotice = nil
        do {
            try store.clear(homeID: homeID)
            historyProblem = nil
        } catch {
            historyProblem = "The old chat couldn't be removed from this iPhone, so it may come back."
        }
    }

    /// Saves the thread to its home's file. A failure is shown above the composer and cleared by
    /// the next save that works (AUD-049: this was a silent `try?`).
    private func persist(homeID: String? = nil) {
        guard let store, let homeID = homeID ?? loadedHomeID else { return }
        // loadNotice already says why: the unread file must not be written over.
        guard blockedHomeID != homeID else { return }
        do {
            try store.save(ConversationDocument(homeID: homeID, messages: messages))
            historyProblem = nil
        } catch {
            historyProblem = "This chat couldn't be saved on this iPhone, so it may be gone next time."
        }
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
        .environment(ReadinessStore(library: HomeLibrary(store: HomeDocumentStore.launchStore().store)))
}
