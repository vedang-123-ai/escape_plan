# How judges get the app

_Written 2026-10-05 (S11.55). Facts about Apple and the CAC come from the pages listed under **Sources**, all read
2026-10-05. Facts about our app come from the repo on `origin/main` the same day._

## What the rules ask

- Judges mainly use the **video and the written answers**. Rules §7.1: "Demonstration Videos and Submission Answers
  will be reviewed and evaluated by the Member of Congress and their office." The CAC guide for congressional offices
  says to give judges "the links to the student Demonstration Videos" and the rubric. It says nothing about judges
  installing apps.
- Judges **may ask** for the app and the code. Rules §7.3: "The Judges have the right to request access to the App and
  source code in person or via any reasonable manner to verify that the App functions and operates as stated in the
  Submission Form. Failure by a Contestant to honor such a request will result in the Submission's immediate
  disqualification."
- So we must be **able** to show the app working and hand over the code when asked. We do not have to put the app on
  every judge's phone. "In person" is named in the rule as an acceptable way.

## What we have today

- **Source code:** the owner decided on 2026-10-05 to make `vedang-123-ai/escape_plan` public. Anyone can then
  download it. Not public yet; see "What the owner must do".
- **Apple Developer Program (paid, $99 a year):** the repo does not say whether the team has one. The Xcode project
  has a signing team id set, but a free Apple Account in Xcode also has a team id, so that proves nothing. The owner
  must check (step 1 below).
- **A real iPhone with LiDAR:** the team has one (an iPhone 17 Pro). A real scan of a friend's house worked on
  2026-09-08 on an earlier build. The final build has not been tested on the phone yet (BLOCKERS §2).
- **The server** runs on Render's free plan at `https://escape-plan-backend.onrender.com`. The first call after it
  sleeps took 42 to 52 seconds in our tests. Every call except `/health` needs a shared password (the "bearer token").
  The AI features return an error today because the server has no working Anthropic key or credits (BLOCKERS AUD-002).

## What works without a LiDAR iPhone (iOS Simulator on a Mac)

Checked by S11.53's simulator walk on 2026-10-05 (`docs/tracker/notes/2026-10-05-s11-53-simulator-walk.md`, BLOCKERS
"S11.53 findings"; merged to `main` in `343fdb6`) and by this session's local server check.

| Works in the Simulator | Does not |
|---|---|
| First launch, the built-in sample homes (a fresh install has four) | LiDAR scanning (RoomPlan needs a LiDAR iPhone or iPad; the app checks `RoomCaptureSession.isSupported`) |
| The 3D House view and the full editor: rooms, doors, windows, stairs, undo and redo | The AI assistant and Import Plan (need a funded Anthropic key on the server; 502 today) |
| Escape routes, the fire simulation, the readiness score and the task list, **when the app can reach a server with the right password** | Anything that needs the phone's real feel: speed, touch, haptics |
| Offline behaviour: the last routes stay on screen when the server is down | |

## The options

| Option | What the judge needs | Cost to us | Time to set up | Risks | Verdict |
|---|---|---|---|---|---|
| **(a) Build from the public repo, run in the Simulator** | A Mac with Xcode 26 (what we use; the project format needs Xcode 16 or newer, not tested on 16) and Python 3.11+ for a local server | $0 | Already possible once the repo is public; README tells them how | Most judges will not have a Mac with Xcode. No LiDAR. Without a server password, routes and score fail | **Offer it, do not rely on it.** Good proof that the code is real |
| **(b) TestFlight** | An iPhone or iPad, the free TestFlight app, an email invite or a public link | $99 a year for the Apple Developer Program. An adult must enroll: Apple requires the legal age of majority and says a parent or guardian can enroll and share it | Enrollment (Apple gives no fixed time) + uploading a Release build + Beta App Review for the first external build (Apple: 50% of reviews in under 24 hours, 90% in under 48) | Needs a privacy policy URL, a beta description and a feedback email before external testing. A build expires after 90 days. The server password ships inside the build (see "Server password") | **Optional extra**, only if a parent enrolls by about Oct 12 |
| **(c) Ad Hoc install** | The judge sends us their iPhone's device id (UDID); we register it and send a signed build | Same $99 membership | Per judge, by hand | 100 devices per type per year, no real problem; but collecting UDIDs from strangers is clumsy and installing an `.ipa` is hard for a non-developer | **No** |
| **(d) Video only** | A web browser | $0 | Already required (rules §4) | Does not by itself satisfy a §7.3 request to see the app work | **Required anyway.** It is the main thing judges see |
| **(e) Show it live: in person, or over a video call** | Being in the room, or a Zoom/FaceTime call | $0 | None beyond a charged phone and a check that the server is awake | The phone must run the final build; the server needs about a minute to wake | **Our answer to a §7.3 request.** The rule names "in person" |

A free Apple Account is not a way around the fee: Xcode's free "Personal Team" can put the app on at most 3 of **our
own** devices, and the install stops working after 7 days. It cannot send the app to a judge.

## Recommendation

**Use (d) + (e) + (a). Add (b) only if a parent pays for the Apple Developer Program by Oct 12.**

1. **The video** is what judges grade. Film the final build on the real iPhone (S11.13).
2. **Public repo** for "access to the source code": a judge can download it, read it, and (with a Mac) run it in the
   Simulator using the README.
3. **If a judge asks to see the app working**, offer a live demo on the team's iPhone, in person or on a video call
   (FaceTime or Zoom screen share). Keep that phone on the final build until judging ends. Wake the server first:
   open `https://escape-plan-backend.onrender.com/health` a minute before.
4. **TestFlight is optional.** It costs $99, needs an adult to enroll, a privacy policy page and up to two days of
   review. It is worth it only if the team wants judges to try the app on their own iPhones. If the owner wants it,
   start enrollment by about Oct 12 so the build is approved well before the Oct 26 deadline.

Cost of the recommendation: **$0**. With TestFlight: **$99**.

## Server password (bearer token) without putting it in the public repo

The token is never in git. `escape_plan/BackendConfig.local.json` is in `.gitignore` (line 21); the app reads
`{"bearer_token": "..."}` from it at launch (`escape_plan/Networking/APIClient.swift`, `bundledBearerToken()`). A full
history scan on 2026-10-05 found no real token, key or password in any commit (S11.55 note).

- **Team iPhone and the filmed build:** a teammate copies `BackendConfig.local.json` into `escape_plan/` on their own
  Mac before building. Xcode bundles it automatically. `python3 scripts/demo-preflight.py` checks it matches the server.
- **TestFlight build:** the same file is bundled into the Release build before Archive. It is still not in git. Be
  aware that anything bundled in an app can be read by a determined person who has the build. That is acceptable
  here because the server limits AI calls per IP and per day, and the token only reaches our own server. **After
  judging ends, change `BACKEND_BEARER_TOKEN` in the Render dashboard** (and the local file), which retires the old one.
- **A judge building from the repo** has no token, and should not get the real one. Two ways, best first:
  1. **Run the server on the same Mac** with any password they choose (checked 2026-10-05: with
     `BACKEND_BEARER_TOKEN=judge-local-token`, `/health` answered, `/routes` with no token gave 401, and `/routes` on
     `schema/fixtures/bungalow.json` with that token gave 200 and real routes). In a Debug build, Settings has
     "Use local dev server (localhost:8000)" and an "Access token" field; type the same password there. Steps are in
     the README.
  2. If a judge cannot run Python, a teammate can send them the real token privately (email, not the repo), and
     change it on Render after judging.
- Release builds hide the server address and token fields (Settings "Advanced" is Debug-only), so the filmed
  build never shows them.

## What the owner must do

1. **Check for a paid Apple Developer membership:** sign in at developer.apple.com/account with the Apple Account
   used in Xcode. If it shows "Apple Developer Program" with a renewal date, TestFlight is available; if it only
   offers to enroll, there is none.
2. **Decide on TestFlight** (yes = $99, a parent enrolls, by about Oct 12; no = live demo plus the video).
3. **Make the repo public** after reading the S11.55 findings in `BLOCKERS.md` (commit emails, the firefighter's
   details in old commits). GitHub: repo Settings, General, Danger Zone, "Change visibility". Then turn on secret
   scanning and push protection (free for public repos) under Settings, Code security.
4. **Keep the team iPhone on the final build** until winners are announced, with `BackendConfig.local.json` in place.
5. **After judging:** change `BACKEND_BEARER_TOKEN` on Render.

### If the owner chooses TestFlight: exact steps

1. A parent or guardian enrolls at developer.apple.com/programs/enroll as an Individual, with their legal name and
   two-factor authentication on, and pays $99. They add the student as a team member in App Store Connect.
2. Write a short privacy policy page (it can be adapted from the app's Settings "What leaves this iPhone?" text) and
   host it somewhere public, for example GitHub Pages on the public repo.
3. In Xcode, set the signing team to that account. Put `BackendConfig.local.json` in `escape_plan/`. Product,
   Archive, then Distribute App, App Store Connect, Upload.
4. In App Store Connect, TestFlight: answer the export-compliance question (the app only uses standard HTTPS), make an
   internal group, then an external group. Fill in the beta description, feedback email and privacy policy URL. Add
   the build to the external group; it goes to Beta App Review.
5. When approved, turn on the public link (set a tester limit, e.g. 50) and paste the link into the submission or
   send it to a judge who asks. The build lasts 90 days; upload a new one if judging runs past that.

## Not verified

- Building in the Xcode **app** (not the command line) on a Mac **without** our team's Apple Account. Our test gate
  builds for the Simulator with `CODE_SIGNING_ALLOWED=NO`, which needs no account. In the Xcode app a stranger may see
  a signing-team message; choosing their own team or "None" should fix it. Logged in BLOCKERS (S11.55).
- Whether the team has a paid Apple Developer membership.
- Whether the CAC portal's own "Submission Checklist" asks for an app link or a code link. We could not read it from
  here (`checklist.md`).

## Sources (all read 2026-10-05)

- 2026 CAC Rules PDF, §3 and §7: https://www.congressionalappchallenge.us/wp-content/uploads/2026/05/2026-CAC-Rules.pdf
- CAC FAQ for congressional offices (judges get video links and a rubric):
  https://www.congressionalappchallenge.us/congress/frequently-asked-questions/
- TestFlight overview (tester limits, App Review for external testers): https://developer.apple.com/testflight/
- TestFlight in App Store Connect (90-day builds, internal vs external):
  https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/
- Inviting external testers (privacy policy URL, review limits, public link):
  https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/
- Enrollment ($99 a year, age of majority, parent can enroll): https://developer.apple.com/programs/enroll/
- Free account vs paid (Personal Team: 3 devices, 7 days): https://developer.apple.com/support/compare-memberships/
- Device registration (100 per type per year, Ad Hoc): https://developer.apple.com/help/account/devices/devices-overview/
- App Review speed (50% under 24 h, 90% under 48 h): https://developer.apple.com/distribute/app-review/
