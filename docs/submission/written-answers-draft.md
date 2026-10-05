# Written answers (draft)

_Drafted 2026-10-05 (S11.51). The 2026 CAC Rules (§4, "Questions") say the form asks questions "similar to" six
listed ones; those come first, in the rulebook's order. The extra questions after them are ones we expect, kept short
so they can be pasted into any similar field. **A team member must read every answer before pasting it**: these are
written in "we" and only the team can confirm they match its own experience. Statistics carry their corpus citation
id so anyone can check them in `backend/corpus/sources.json`._

**Do not paste the AI-assistant sentences if the Anthropic account is still unfunded on submission day** (see
[`checklist.md`](checklist.md)). Live AI behaviour has never been verified; its safety checks pass in stub tests only.

---

## The six questions from the 2026 CAC Rules

### 1. What is the title of your app?

Escape Plan

### 2. Explain the app's purpose.

Escape Plan helps families make, check and practise a home escape plan before an emergency happens, using a 3D model of
their own home.

(One sentence, as the rules ask for in the video. Longer version: [`app-description.md`](app-description.md).)

### 3. What inspired you to create this app?

In a home fire you may have as little as two minutes to get out after the smoke alarm sounds
[cite: redcross-two-minutes], yet the Red Cross reports that only about 26% of families have made and practised an
escape plan [cite: redcross-escape-fact-sheet]. Drawing a plan by hand is easy to put off, and it is hard to know if
the plan is any good: is the bedroom window big enough, can Grandma use the stairs, what if the fire starts in the
kitchen? We wanted an app that does that checking for a family using the shape of their real house. Talking to a
working firefighter then shaped what it became: he told us it fits prevention and education, not use during a fire.

### 4. What technical difficulty did you face, and how did you address it?

The hardest part was making escape routes that are both correct and trustworthy on a home the family can change.

- **A model that survives editing.** Doors and windows are stored as a position along a wall, not as fixed
  coordinates, so when you drag a wall in the editor its doors move with it, and the routes update.
- **Routes that fit each person and each emergency.** We turn the home into a graph of rooms, doors, windows and
  stairs and run a shortest-path search (Dijkstra) for every room. A person tagged as having limited mobility has
  stairs and windows removed from their graph; a child's window exits are made more costly. For the fire simulation,
  we spread the fire through the same graph room by room, mark the rooms the fire reaches first, and re-solve
  everyone's route around them until nothing changes.
- **AI that cannot make things up.** We did not let the AI compute routes at all. For the assistant, our server checks
  every source tag against our library of 36 sources (FEMA, NFPA, the Red Cross, USFA, NOAA, USGS and others). If an answer
  gives safety advice without a valid source, it is asked once to fix it, and otherwise replaced by an honest "we
  can't back that up" message. This is verified in our tests with a stand-in for the AI; we have not been able to
  test it against the live AI, because our AI account is out of credits.

### 5. What did you learn while participating in the CAC? What was your biggest takeaway?

See the short answer at the end of [`what-we-learned.md`](what-we-learned.md). In one line: talk to the people who
do the job before deciding who your app is for. A firefighter told us our idea fits prevention, not firefighting,
and we rebuilt the app around that.

### 6. What would you change about your app if you were to create a 2.0 version?

- Test the whole app on real iPhones, including older iOS versions, and tune the 3D camera and speed by feel. Our
  latest build has only been tested in the simulator so far.
- Run the routing engine on the phone itself, so the full plan works with no internet. Today it runs on our server,
  and the app keeps only the last routes it received for offline use.
- Make the earthquake and tornado modules deeper. Fire is checked against building-code numbers; the other two follow
  FEMA and NOAA guidance because there are few codified numbers to use, and we label them that way.
- Help fire departments hand the app out as part of their education programmes, which is what the firefighter
  suggested (a department shares a QR code, and the family scans their home).

---

## Questions we expect on the form

### What problem does it solve?

Most families have never made and practised a home escape plan, and a plan drawn on paper cannot tell you whether a
window is big enough to climb out of or whether every person can actually use the route. Escape Plan builds that
plan from a model of the real home and checks it.

### Who does it help?

Families, especially households with someone who needs a different way out: young children, older relatives, or
someone who cannot use stairs. Each person gets their own route.

### How does it work?

1. Scan the home with an iPhone's LiDAR sensor (Apple RoomPlan), or draw it in the app. A 3D editor fixes whatever
   the scan missed.
2. Our deterministic Python engine computes a main and, where one exists, a backup escape route from every room, for each person, plus
   earthquake cover and the safest room in a tornado.
3. The app shows the routes animated on a 3D "dollhouse" of the home, runs a fire simulation from any room, and gives
   a readiness score and a checklist for fire, earthquake and tornado.
4. The family can print the plan and, if they choose, share a snapshot with their fire department.

Built with Swift and SwiftUI (iOS app), SceneKit (3D), RoomPlan (scanning), Python with FastAPI (engine and server,
hosted on Render), and the Anthropic API (assistant). Full list: `docs/tools-used.md`.

### What is original about it?

- A full 3D home editor we built, so a scan is a starting point rather than the final answer.
- Our own routing engine and fire-spread simulation. Same home in, same routes out, every time.
- A hazard engine where every finding carries a source and an action, plus the measurement and threshold where a
  code number exists.
- Honest labelling: fire is checked against code numbers, while earthquake and tornado are marked "Guidance-based".
- A safety library of 36 sources we collected and paraphrased, with a citation on every claim, checked automatically.

### How is AI used, and how is it not used?

**In the app:** an AI assistant (Anthropic's Claude) answers questions about your home, and an optional "Import Plan"
feature drafts a home from a description or a photo, which the family must review in the editor before it is
scored. **The AI never computes a route, a score or a hazard finding**; our engine does. **It cannot invent safety
advice**: the server only accepts safety advice that cites a source in our library. These checks are verified in our
tests with a stand-in for the AI; the live AI is unverified because our account is out of credits.

**To build the app:** we used AI coding tools, Claude Code (Anthropic) and Google Antigravity (Gemini), and Claude
Design for a visual prototype. Most commits in our repository were made with Claude Code's help. Everything is
disclosed in `docs/tools-used.md`, as the rules require.

> **For the team to finish before pasting:** add one or two sentences in your own words on what each of you
> personally designed, decided, built or checked. The rules expect "significant individual contributions and
> technical understanding", and only you can state that.

### What challenges did you face?

- **The AI account ran out of credits.** Because the AI was kept separate from the engine, routes, simulation, score
  and checklist kept working; only the AI features stopped.
- **Our first idea was wrong about who it was for.** A firefighter told us the app fits prevention, not use during a
  fire, and we changed the product.
- **We could not test everything on a real phone.** A real LiDAR scan of a friend's house worked on 2026-09-08, but
  the full on-device test of the final build has not happened yet; the latest build is tested in the simulator.
- **Saying no.** We cut an AR walk-through, photo object recognition, and accounts with cloud sync so that what is
  left is reliable.

### What is next?

See question 6 above.
