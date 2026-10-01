# S11.16 — Privacy copy says what actually leaves the phone (AUD-050, AUD-018)

- **Who:** Anish (with Claude)
- **Date(s):** 2026-10-01
- **Branch:** `s11-16-privacy-truth`
- **Status when I stopped:** done. The disclosure separates "sent to compute, not stored" from "saved to an account", names
  Anthropic, and says what stays on the device. Tests pin it against real request encodes.

## The inventory (the evidence for every sentence)

Re-derived on `origin/main` `7723478` by reading every iOS request body and its server handler. "Account?" means whether
the request needs a signed-in user. Every compute endpoint runs on the build's shared bearer token, so **all of them run
signed out**.

| Endpoint | iOS caller | Fields sent | Account? | Stored server-side? | Forwarded to Anthropic? |
|---|---|---|---|---|---|
| `POST /score` | `ReadinessStore` (Home tab, every checklist tick) | `home` (whole HomeModel), `checklist_state` | no | no | no. `include_recommendations` would, but the app never sends it (defaults `False`, `main.py`) |
| `POST /routes` | `fetchRoutesCached` (House, drill) | `home`, `peril?`, `constraints?`, `profile_id?` | no | no | no (pure engine) |
| `POST /evacuate` | `HouseScreen`, `DrillScreen` | `home`, `origin_room_id`, `profile_set_id?` | no | no | no (pure engine) |
| `POST /convert` | `HomeScreen` (after a scan) | `scan` (RoomPlan measurements: surfaces, objects, categories, confidences, `appVersion`, `deviceModel`; no image data, `RawScanExport.swift`), `home_name` | no | no | no |
| `POST /diff_obstructions` | `HomeScreen` re-check | `stored_model`, `scan_model` (both whole homes), `target_room_id` | no | no | no |
| `POST /chat` | `AssistantScreen` | `home`, `messages` (no `profiles`, `APIClient+Chat.swift`) | no | no (stateless, `service.py` docstring) | **yes**: `summarize_home` (home name, floor names, room names/types/ids, exits, stairs; no profiles, meta or household) + the message history, including earlier replies |
| `POST /build` | `BuildFromPlanView` (Import Plan) | `description?`, `image_b64?` (photo as its original bytes, EXIF included; or page 1 of a PDF rendered to PNG), `image_media_type` | no | no | **yes**: the image and the description (`ai/builder.py`) |
| `POST /analyze`, `POST /explain` | **none** (defined in `APIClient+Analyze.swift`, never called) | `home` | — | no | yes, but unreachable from the app |
| `POST /auth/register`, `/auth/login` | `AuthClient` | email, password | — | email + argon2id hash (`auth/passwords.py`) | no |
| `GET/DELETE /auth/me` | `AuthClient` | JWT | yes | delete removes user + homes | no |
| `GET/POST /homes`, `DELETE /homes/{id}` | `CloudHomesClient` (sync) | whole HomeModel | yes | **yes** (Mongo `homes`) | no |

Storage check: the only Mongo writes are in `api_auth.py` / `cloud_repo.py` (`/auth/*`, `/homes`). No handler logs a
request body (every `logger.*` call in `backend/app` checked; they log counts, ids and errors). No other networking in
`escape_plan/` (`URLSession`/`URLRequest` appear only in `Networking/`, `Auth/AuthClient.swift`,
`Sync/CloudHomesClient.swift`). No `CoreLocation`, no analytics SDK.

Not synced (AUD-018): `ChecklistStateStore` (UserDefaults `checklistState.<home_id>`), the drill log, and
`ConversationStore` (`Documents/Assistant/conversation.json`). `CloudHomesClient` sends the HomeModel only.

## What happened

- `AccountPrivacy.swift`: new `signedOutSummary`; new `computeRequestKeys` + `sentToCompute` (keyed like `uploaded`),
  `sentToAnthropic`, `notSynced` (AUD-018). The password moved from "never uploads" (it is sent, once) to the account
  list as "a one-way hash". The camera line now says frames never leave the phone and names Import Plan as the exception.
- `AuthFormComponents.swift` (layout only): five lists — sent to compute and not stored; passed on to Anthropic; saved to
  your account only if you sign in; kept on this iPhone, not in your account; never leaves this iPhone. Button is now
  "What leaves this iPhone?" (was "What does an account upload?", which pointed at the opt-in path and away from the
  one everybody takes).
- Tests: `AccountPrivacyTests` encodes a real `ScoreRequest` and a fully-populated `RoutesRequest` (both runners) and
  `EvacuateRequest`/`DiffRequest`/`ChatRequest`/`BuildRequest` (app runner only, they live in `Networking/`), and asserts
  every top-level field is described by a line of copy; also that the `home` sent to compute is the whole document,
  and a regression guard that no line says "uploads nothing" or "ever sent". Mutation-checked: dropping
  `checklist_state` from the copy fails two tests. `SignedOutProofTests` header now says it proves the **sync** half only.
  `SignedOutPathUITests` asserts all five list identifiers and the new button label.

## Evidence

- `grep -rn "uploads nothing\|ever sent" escape_plan escape_planTests` → only `AccountPrivacyTests.swift:180-181`
  (asserting absence), plus two lines this session does not own and that are not privacy-disclosure claims about the
  server: `Screens/HouseScreen.swift:800` (a code comment, "a backend that ever sent `false`") and
  `Screens/ConsentSheet.swift:66` ("Nothing is ever sent automatically — you pick the app…", the share-sheet consent,
  which is true: the snapshot leaves only through the share sheet). Logged in BLOCKERS rather than edited.
- `swift test --package-path tools/editorcore`: **652 passed, 0 failures** (645 before, +7 new shared tests).
- `bash scripts/typecheck-ios.sh`: ok ×4 (app debug, app release, tests, UI tests).
- Simulator, `xcrun xcresulttool get test-results summary --path /private/tmp/claude-501/s1116.xcresult` (iPhone 17 Pro,
  iOS 26.5, `-only-testing` `SignedOutPathUITests` + `AccountPrivacyTests` + `SignedOutProofTests`): **29 passed,
  0 failed, 0 skipped** (6 UI + 16 + 7). S11.8 has landed, so the UI tests were run. Re-run after the auditor fixes on the final code: `s1116b.xcresult`, **29 passed, 0 failed**.
- Eyeballed on the simulator: Settings, signed out, "What leaves this iPhone?" expands to all five lists; text wraps,
  nothing clipped.

## Decisions / surprises

- "The server does not store it" is the claim (first draft said "does not keep it"; the security-reviewer pointed out
  "keep" reads as covering the host's platform logs too). Not "deleted after N minutes" or "encrypted": nothing in the
  code promises either.
- The copy does not say how long **Anthropic** keeps what it is sent; it says Anthropic handles it under its own
  policies. The location line now admits the server sees each request's IP address (security-reviewer), and the
  re-scan line no longer files the saved home under "scan measurements": `/diff_obstructions` sends the whole saved
  home, so `stored_model`/`scan_model` moved to the "whole home" line.
- AUD-018 wording is "kept on this iPhone and not copied to your account", deliberately not "never leaves": ticks go to
  `/score` and chats go to `/chat` and Anthropic; they are just not saved by the server.
- `/analyze` and `/explain` are reachable server-side but have no caller in the app (AUD-022), so the copy does not list
  them. If S11.39 wires the AI inspector, `sentToAnthropic` must gain a line — `/analyze` sends the home to the agent.

- **pitch-truth-auditor corrections** (applied): the S11.7 line "your home's address — only if you typed one in" was
  false (no screen sets `meta.address_optional`); the copy now says the app never asks for an address. Added the `pet`
  tag. The summary now says the assistant sends room names, not just "what you type". The scan line lists labels, app
  version and iPhone model. The location line says a picked photo is sent with any location saved in it. The analytics
  line no longer says the logs never contain request content: `/convert` logs converter warnings that include
  RoomPlan-derived room labels (`main.py`, `converter.py`).
- Two code bugs found by the auditor, logged in BLOCKERS rather than fixed (not owned): delete-on-401 reports success
  after a token expires; Import Plan sends photo metadata.

## Questions for teammates

- @S11.39 owner: wiring `/analyze` changes what Anthropic receives (the agent's tool results over the whole home).
  Update `AccountPrivacy.sentToAnthropic` in the same change.
- @S11.13 owner: the App Store privacy label must match this copy (BLOCKERS, S11.16 findings).

## Next steps

- S11.13: privacy label (see BLOCKERS).
- S11.43 (session length) can now build on this copy; it lists S11.16 as a prereq.
