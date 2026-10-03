# Feature inventory — keep or cut for the demo

_Written 2026-10-02 from the shipped screens on `main` (91552f3). **Decided by Anish the same day** (Decision column);
trim 1 and trim 2 carry it out, and the AI rows wait for the next pass. "Take" is a recommendation; the owner decides. The older, status-by-capability view is
[`../capabilities.md`](../capabilities.md); open problems found while writing this are in
[`../tracker/end-of-project-fixes.md`](../tracker/end-of-project-fixes.md)._

**Mark-up key:** change the `Decision` column to `KEEP`, `CUT` or `HIDE` (still in the code, not reachable in the demo
build). A cleanup session will work from this column.

## Home tab

| Feature | What it does | Take | Decision |
|---|---|---|---|
| Scan New Home | LiDAR room scan that builds the 3D house | Keep. It is the core of the app || KEEP |
| Build Manually | Start from a blank house and draw it | Keep, as a quiet backup || KEEP |
| Import Plan | Describe the house or upload a photo; the AI drafts it | Cut or hide. The AI is off and it is not in the story || DECIDE NEXT PASS (AI) |
| Home switcher, Manage homes | Switch, delete or duplicate homes | Keep || KEEP |
| Preparedness score + breakdown | 0–100 score and what is costing points | Keep. Judges like a number || KEEP |
| Up next | The top three tasks | Keep || KEEP |
| Prevention tip | One cited safety tip | Optional || KEEP (firefighter: useful) |
| Re-scan review | After re-scanning a room, shows what changed | Cut. Too niche for the demo || CUT (trim 1) |

## Tasks tab

| Feature | What it does | Take | Decision |
|---|---|---|---|
| Readiness checklist | Urgent / To do / Done, filtered by fire, earthquake or tornado | Keep || KEEP |
| Outside meeting point | Where the family meets outside | Keep. Quick, real advice || KEEP |
| Printable plan (PDF) | One-page escape plan to print or share | Keep. A tangible result || KEEP |

## House tab

| Feature | What it does | Take | Decision |
|---|---|---|---|
| 3D house view + editor | Add or remove rooms, doors, windows, stairs, furniture and floors; rename, rotate, undo/redo | Keep. The "finishing touches" after the demo cut happen here || KEEP |
| Escape routes | Animated route per person and per disaster, with step-by-step directions | Keep. The heart of the app || KEEP |
| Route check issues | Flags problems such as "window too high" or "furniture narrows the path" | Keep || KEEP |
| Fire simulation | Start a fire in a room and watch everyone re-route around it | Keep. The most impressive moment || KEEP |
| Confirm AI draft | Review step for a house made by Import Plan | Goes with Import Plan || DECIDE NEXT PASS (AI) |
| Hazard Hunt | Room-by-room questions ("Is the bookcase strapped to the wall?") | Cut (owner's instinct). It feeds most earthquake findings, but slows the demo || CUT (trim 1) |

## Practice

| Feature | What it does | Take | Decision |
|---|---|---|---|
| Practice drill | Walks the family through the plan step by step, timer vs the modeled time | Keep only if it fits the video || CHANGED (trim 2, done 2026-10-03): "Run a fire drill" opens House's fire simulation, 0.25×–2×, with a "Who does what" card per person |
| Practice log + reminders | Records practice runs and schedules a nudge to repeat | Cut or hide || CUT (trim 2, done 2026-10-03). The drill task is now ticked by hand |
| Walk it in AR | Shows the route through the phone camera | Cut. Never tested on a real iPhone, a big demo risk || CUT (trim 2, done 2026-10-03; code deleted) |

## Other tabs and screens

| Feature | What it does | Take | Decision |
|---|---|---|---|
| Assistant tab | Chat about your home; answers cite FEMA, NFPA, Red Cross | Keep only if the AI key is added. Backs the "not an AI wrapper" answer || DECIDE NEXT PASS (AI) |
| Household profiles | People and pets (child, elderly, limited mobility), each with their own route | Keep. Makes the routes personal || KEEP |
| First-run walkthrough | Intro and household questions | Keep, short || KEEP |
| Share with fire department | Opt-in floor-plan snapshot for responders | Keep. The firefighter angle || KEEP (firefighter: useful) |
| Accounts + cloud sync | Optional login and backup | Hide. Already absent from the pitch || CUT, switched off (trim 1) |
| Server address + token | Developer settings | Hide from normal users || KEEP |

## The story if every suggested cut is taken

Scan → edit (finishing touches) → routes for each person → fire simulation → score and checklist → printable plan,
with household profiles and the Assistant supporting.
