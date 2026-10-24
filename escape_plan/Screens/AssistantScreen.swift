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
                    if let tooLong = ChatHistory.tooLongNotice(for: draft) {
                        // Live, so the person sees why Send is off before they press it.
                        Label(tooLong, systemImage: "text.badge.xmark")
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
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
    private let suggestions = ["What should I fix first?", "Why does my route go this way?",
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
            && ChatHistory.tooLongNotice(for: draft) == nil
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
        // Too long for the server: the draft stays in the box to be shortened (S11.50).
        guard ChatHistory.tooLongNotice(for: text) == nil else { return }
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
    /// stays there on failure; the error banner offers Retry instead of dropping it. Only for
    /// Anish's House, and only when the server cannot answer (no AI credit, a gateway error,
    /// offline), the pre-written sample turn is shown instead, labelled as a sample.
    private func deliverPendingUserMessage() {
        guard let home else { return }
        // A thread saved before S11.50 can end in a message the server will refuse for length:
        // say so plainly rather than send it for a vague 422.
        if let last = messages.last, last.role == .user,
           let tooLong = ChatHistory.tooLongNotice(for: last.content) {
            failure = .chatMessageTooLong(tooLong + " Start a new chat to ask it again.")
            return
        }
        isSending = true
        failure = nil
        // The most recent turns that fit the server's caps; the full thread stays on screen.
        let history = ChatHistory.trimmed(messages.map(\.wireMessage)).messages
        let askedAbout = home.home_id
        let turnIndex = messages.filter { $0.role == .assistant }.count

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
                    if DemoAssistantScript.covers(homeID: askedAbout),
                       APIClient.isRecoverableRouteFailure(error) {
                        let sample = DemoAssistantScript.response(forTurn: turnIndex)
                        messages.append(
                            AssistantMessage(role: .assistant,
                                             content: DemoAssistantScript.sampleLabel + sample.reply,
                                             citations: sample.citations)
                        )
                        persist(homeID: askedAbout)
                    } else {
                        failure = BackendFailure(error, while: .assistant)
                        Haptics.warning()
                    }
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

// MARK: - Pre-written sample conversation (Anish's House)

/// Shown only when the live assistant cannot answer, only for Anish's House, and always under
/// `sampleLabel`, so a pre-written turn is never passed off as a live answer.
private enum DemoAssistantScript {
    /// The bundled fixture's fixed `home_id` (seeded verbatim by `FixtureSeeder.seedOwnedHomes`).
    static let homeID: String? = try? FixtureLoader.load(.anishsHouse).home_id

    static func covers(homeID: String) -> Bool { homeID == self.homeID }

    static let sampleLabel = "_Sample conversation: the live assistant is offline, so this is a pre-written answer for Anish's House._\n\n"

    static let turns: [ChatResponse] = [
        // Turn 1: "What should I fix first?" — comprehensive LiDAR scan & hazard review
        ChatResponse(
            reply: """
            Based on the 3D RoomPlan scan of **Anish's House** (14 rooms across **Ground Floor** and **Upstairs**) and our oriented-bounding-box (OBB) topple and egress analysis, here is what you should fix first, ranked by life-safety impact:

            **1. Critical Egress Pinch in Bedroom 2 (High Priority)**
            • Our spatial solver detected an unsecured **1.83 m (6 ft) tall wardrobe** (`1.00 × 0.56 m` footprint at `x=7.20, y=3.82`) standing **0.0 m** from the **Bedroom 2 → Landing** doorway (`0.81 m` clear width).
            • In an earthquake, its `1.83 m` topple arc sweeps directly across the door swing, sealing off the primary **13.4 m** interior stair route down to the front door and forcing reliance on the secondary window (`2.1 m` away) [cite: shakeout-guidance, nfpa-escape-planning].

            **2. Unstrapped Water Heater Beside Utility Shutoffs in Laundry (High Priority)**
            • The **1.52 m water heater** (`0.56 × 0.56 m` at `x=10.85, y=4.00`) in **Laundry** is unbraced (`secured: false`) and sits **0.71 m** from the **Kitchen–Laundry** doorway (`0.81 m` wide), right between your **main water shutoff** (`10.50, 3.82`) and **electrical panel** (`11.04, 4.40`).
            • Anchor it to wall studs using two heavy-gauge metal straps and verify flexible gas and water connectors [cite: shakeout-guidance, ca-hsc-19211].

            **3. Unsecured Elevated TVs in Living Room & Primary Bedroom**
            • **Living Room 65" TV:** The scan captured a `1.45 × 0.84 m` display mounted at **1.02 m elevation** on the south partition wall (`x=2.62, y=5.33`, `secured: false`), directly facing the `2.21 m` sofa across your **10.8 m** primary route to the **Foyer**.
            • **Primary Bedroom 50" TV:** A second `1.12 × 0.65 m` display is mounted at **1.20 m elevation** on the east wall (`x=4.47, y=2.60`, `secured: false`) along the path between the bed and the **Landing** door. Secure both with dedicated VESA TV safety straps rather than standard furniture hardware [cite: shakeout-guidance].

            **4. Secondary Egress Window & Doorway Topple Risks**
            • **Living Room Bookcase:** A **1.83 m tall bookcase** (`x=0.20, y=4.10`) stands just **0.30 m** from your secondary egress window (`0.91 × 1.37 m`, `0.61 m` sill), inside its tip-over shadow [cite: shakeout-guidance, irc-2021-r310].
            • **Bedroom 3 & Primary Bedroom:** The **1.52 m bookcase** in **Bedroom 3** sits **0.55 m** from the **Landing** doorway, and the **0.86 m dresser** in **Primary Bedroom** sits **0.38 m** from the **Primary Bathroom** door [cite: shakeout-guidance].

            **5. Kitchen Range Clearance & Missing Smoke Alarms**
            • In **Kitchen**, the **1.78 m refrigerator** (`x=5.10, y=9.08`) sits **0.47 m** from the **range** (next to the gas shutoff at `6.40, 9.30`)—under the **0.91 m (3 ft)** clearance NFPA recommends [cite: nfpa-heating-safety, nfpa-cooking-safety].
            • Finally, no smoke alarms are logged in your household profile yet: install interconnected alarms inside **Primary Bedroom**, **Bedroom 2**, and **Bedroom 3**, on the upstairs **Landing**, and on the **Ground Floor** [cite: usfa-smoke-alarms].
            """,
            citations: [
                "ca-hsc-19211",
                "irc-2021-r310",
                "nfpa-cooking-safety",
                "nfpa-escape-planning",
                "nfpa-heating-safety",
                "shakeout-guidance",
                "usfa-smoke-alarms"
            ]
        ),

        // Turn 2: Optimal placement & securing strategy for the TVs and tall furniture
        ChatResponse(
            reply: """
            To find the safest placements without sacrificing floor space, I ran our room-polygon and A* clearance check across the wall segments in **Bedroom 2**, **Living Room**, and **Primary Bedroom**:

            **1. Relocating the Bedroom 2 Wardrobe (`1.00 × 0.56 × 1.83 m`)**
            • **Why the current spot fails:** At `(7.20, 3.82)` on the south partition wall, its `1.83 m` height exceeds the `0.0 m` offset to the **Landing** doorway (`d_landing_bed2`) and sits adjacent to the desk (`x=7.45, y=0.40`).
            • **Optimal placement:** Move the wardrobe to the **east exterior wall south of the side window** (`x=10.90, y=3.10`, between `t=0.62` and `t=0.95` of edge 1) or along the **north wall gap at `x=8.55, y=0.30`** between the desk and the bed (`x=9.90, y=1.20`).
            • **Result:** This opens **2.15 m of clear radius** around the **Landing** doorway so the **13.4 m** primary stair route can never be pinched, keeps the wardrobe outside the bed's fall zone, and lets you anchor it directly into exterior wall studs with two metal L-brackets [cite: shakeout-guidance, fema-earthquake].

            **2. Living Room 65" TV (`1.45 × 0.08 m` at `1.02 m` elevation) & `1.83 m` Bookcase**
            • **TV placement is already geometrically optimal:** The south wall segment at `(2.62, 5.33)` sits centered between the **Dining Room** opening (`1.52 m` wide) and the **Foyer** doorway (`1.22 m` wide). Because its depth is only `0.08 m` at `1.02 m` elevation, it does not encroach on the A* navigation corridor, and it avoids direct window glare from the north window (`1.52 m` wide). Keep the TV at `(2.62, 5.33)`, lock the mount's tilt latches, and install dual VESA safety straps into the studs [cite: shakeout-guidance].
            • **Bookcase relocation:** Slide the `1.83 m` bookcase (`0.36 × 0.92 m`) **1.4 m north along the west wall** from `(0.20, 4.10)` to `(0.20, 1.80)`. That increases clearance to the side egress window from **0.30 m to 1.70 m**, completely freeing your **2.5 m** secondary window exit, then stud-strap the top rail [cite: shakeout-guidance, nfpa-escape-planning].

            **3. Primary Bedroom 50" TV (`1.12 m` wide at `1.20 m` elevation) & Dresser**
            • Keep the TV on the east wall at `(4.47, 2.60)`—it sits `1.7 m` north of the **Landing** door (`0.86 m` wide) and `1.4 m` clear of the bed's footprint (`x=2.31, y=1.25`)—and add UL-listed TV straps [cite: shakeout-guidance].
            • Shift the `0.86 m` dresser **0.65 m east** along the south wall from `(1.50, 5.18)` to `(2.15, 5.18)` so its `0.38 m` overlap with the **Primary Bathroom** doorway drops to zero [cite: shakeout-guidance].
            """,
            citations: [
                "fema-earthquake",
                "nfpa-escape-planning",
                "shakeout-guidance"
            ]
        ),

        // Turn 3: Upstairs escape routes, IRC R310 window check & 2-minute drill plan
        ChatResponse(
            reply: """
            Here is how the routing engine mapped your **Upstairs** (`2.59 m` ceiling height) and **Ground Floor** (`2.74 m` ceiling height) escape paths, along with how to run your family drill:

            **1. Upstairs Primary vs. Secondary Routes ("Two Ways Out")**
            • **Primary Bedroom:** Your fastest direct egress is the west side window (`2.3 m` travel, `0.91 × 1.22 m` opening at `0.61 m` sill height), and your primary interior route runs through the **Landing** door (`0.86 m` wide), down the straight stairs (`s_main`) into the **Foyer**, and out the **front door** (**14.8 m** total) [cite: nfpa-escape-planning, irc-2021-r310].
            • **Bedroom 2 & Bedroom 3:** Interior routes cross the **Landing** and descend the **Foyer** stairs to the front door (**13.4 m** from **Bedroom 2**; **14.7 m** from **Bedroom 3**), with the **Kitchen back door** (`16.7 m` from the **Landing**) as a backup ground exit.
            • **IRC R310 Window Verification:** Every upstairs bedroom window (`w_primary_side`, `w_bed2`, `w_bed2_side`, `w_bed3`) measures **0.91 m wide × 1.22 m high (`1.11 m²` area) with a 0.61 m sill**, passing the 2021 IRC R310 emergency escape requirements (min `0.508 m` width, `0.610 m` height, `0.53 m²` opening, max `1.118 m` sill) [cite: irc-2021-r310].

            **2. How to Run Your 2-Minute Household Drill**
            • **Stage Second-Floor Escape Ladders:** Store a collapsible escape ladder beneath the window in **Primary Bedroom**, **Bedroom 2**, and **Bedroom 3**. During a drill, practice hooking and deploying it from a first-floor window only, never from the second story [cite: nfpa-escape-planning, usfa-escape-plans].
            • **Practice Blocking the Foyer Stairs:** Run Drill Pass A down the **Foyer** stairs to the **front door** (`2.7 m` from **Foyer**). Then run Drill Pass B assuming smoke blocks the front foyer—routing through the **Foyer → Kitchen** door (`0.91 m` wide) and out the **Kitchen back door** (`3.1 m` across the **Kitchen**), closing every bedroom door behind you to slow smoke and heat [cite: nfpa-escape-planning, redcross-escape-plan].
            • **Clock the 2-Minute Benchmark:** Start a timer from the bedrooms with the longest interior travel (**Primary Bedroom** at `14.8 m` and **Bedroom 3** at `14.7 m`) and verify everyone reaches your outside meeting point in under **2 minutes**, repeating the drill twice a year [cite: redcross-two-minutes, redcross-escape-plan].
            """,
            citations: [
                "irc-2021-r310",
                "nfpa-escape-planning",
                "redcross-escape-plan",
                "redcross-two-minutes",
                "usfa-escape-plans"
            ]
        ),

        // Turn 4+: Wrap-up if an additional message is sent
        ChatResponse(
            reply: """
            Once you complete those fixes—relocating and strapping the **Bedroom 2 wardrobe**, strapping the **Laundry water heater** and both **mounted TVs**, sliding the **Living Room bookcase** clear of the side window, and checking off your **5 smoke alarm locations** on the **Tasks** tab—every high-severity topple and egress warning in **Anish's House** will be resolved [cite: shakeout-guidance, usfa-smoke-alarms].

            You can also export your **Fire Department & Family Escape Plan PDF** from the **Home** tab once you set your outside meeting place so everyone has the floor plan, shutoff locations (`Laundry` water/electrical and `Kitchen` gas), and primary/secondary routes in one sheet [cite: nfpa-escape-planning, redcross-escape-plan].
            """,
            citations: [
                "nfpa-escape-planning",
                "redcross-escape-plan",
                "shakeout-guidance",
                "usfa-smoke-alarms"
            ]
        )
    ]

    static func response(forTurn turnIndex: Int) -> ChatResponse {
        let clamped = min(max(0, turnIndex), turns.count - 1)
        return turns[clamped]
    }
}

// MARK: - Message bubble

/// One turn. Assistant text is rendered with inline Markdown formatting while preserving
/// inline `[cite: source-id]` tags verbatim (grounding is the feature, not noise) —
/// with the server's citation id list echoed as chips underneath.
private struct MessageBubble: View {
    let message: AssistantMessage

    private var isUser: Bool { message.role == .user }

    private var formattedContent: AttributedString {
        if let attributed = try? AttributedString(
            markdown: message.content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(message.content)
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 8) {
                Text(formattedContent)
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
