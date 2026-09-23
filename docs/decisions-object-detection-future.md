# Object detection: what it means here, and what would have to change

**Status: settled 2026-09-22 (S11.3). Supersedes the scoping half of the cancelled S10.2.**
This page answers one question a judge, a teammate or a future session will ask: *"you say
the app detects hazards — detects them how, and why not with a model?"* The rule book is
[`object-hazard-spec.md`](object-hazard-spec.md); this is the decision behind it.

---

## 1. What "detection" means in this app

Three mechanisms, none of them a learned detector:

| Mechanism | What it produces | Where it comes from |
|---|---|---|
| **RoomPlan LiDAR scan** | ~16 classes of furniture and appliance with 3D oriented bounding boxes, mapped to the schema's object categories (spec §7) | Apple's on-device model, shipped with iOS |
| **Guided manual tagging** | the objects no scan can see — the space heater, the water heater in the closet, the mirror over the bed, and above all *whether the bookcase is strapped* | the hazard hunt, a room-by-room editor flow |
| **The deterministic rules engine** | the findings themselves: R1–R6, each carrying a measured value, the threshold it violates, a citation, and an action | `backend/app/routing/object_hazards.py`, pure functions |

**The detection is Apple's; the judgment is ours, and the judgment is the product.** RoomPlan
answers "there is a 2.1 m storage unit at (9.4, 3.1), rotated 12°". It does not answer "that
unit is unsecured, its topple arc covers the pillow end of the bed, and ShakeOut says strap it
first." Spec §2 bans the first sentence as an output and requires the second. Everything this
app adds sits after the bounding box.

So the honest phrasing, everywhere — pitch, script, README, app copy — is **"measures the home
against codified standards"**, never "detects hazards with AI".

### What it deliberately cannot do

RoomPlan will never see a backpack, a power strip, an extension cord under a rug, or a tower
fan. The app therefore never claims clutter detection. Transient clutter has three honest
substitutes, all shipped: recurring `recurrence_days` checklist items ("keep exits clear"), the
hazard hunt for semi-permanent items the user tags, and the exit-path re-check that diffs a
fresh partial scan against the stored model and reports *something new is in the corridor*
without pretending to know what it is.

And `secured` — the single field that decides whether R1 and R5 fire at all — is **not
detectable by any camera or LiDAR sensor at any price**. A strap behind a wardrobe is occluded
by the wardrobe. No amount of model quality moves that; it is a question, and the hazard hunt
asks it.

## 2. What was tried

**S7.9, 2026-09-10 — a timeboxed Vision feasibility spike. Verdict: NO-GO.**
`VNClassifyImageRequest` (Apple's built-in on-device classifier, no training) was run over
representative photos of the five target classes. The gate, written into the session's
acceptance *before* the spike ran, was 2+ target classes receiving a usable label mapping.

| Target class | Top label | Usable? |
|---|---|---|
| Space heater | `structure` (96%) | no |
| Water heater | `structure` (93%), `portal`, `window` | no |
| Bookcase | `structure` (98%), `conveyance`, `portal` | no |
| Wall-mounted TV | `television` (77%) | **yes** |
| Wall mirror | `structure` (72%), `art`, `decoration` | no |

1 of 5. The spike is `docs/tracker/notes/2026-09-10-s7-9-vision-spike.md`; the ruling is
`docs/decisions.md`, 2026-09-10 ("S7.9 Vision Feasibility NO-GO"), which cut S7.10.

Two things are worth keeping from that result. The classifier is a *scene* classifier, not an
object detector — `structure` and `portal` are the labels of something working correctly on
the wrong task. And the one class it got right, the television, is the one class **RoomPlan
already returns for free**. The spike's honest conclusion is not "Vision is bad"; it is "this
Vision API adds nothing over the scan for the classes that matter."

**Custom or trained ML was rejected at scoping**, before any of this, and is a standing term of
the scope lock (product spec §4; `decisions.md` 2026-09-08). The reason is not effort: an
accuracy failure in a safety app is worse than an absence. A missed hazard reads as a
clearance. There is no user-visible confidence dial that makes "we think there might be a
bookcase" useful advice.

## 3. What would have to be true before revisiting

Not "should we use ML" — that is unanswerable in the abstract. These are the falsifiable
conditions, in the order they would have to fall. **All five, not any.**

1. **A real failure this cannot fix first.** A documented hazard the current mechanism misses
   *and* that the hazard hunt cannot ask about. Today's list is the opposite: the S10.1 QA pass
   found four defects and every one was a logic bug in the rules engine — a false positive
   between two heat sources, a room-assignment filter, a double-fired rule, a wrong noun. Four
   for four fixed in S11.3 by reading the code. None was a perception failure. **Fix the
   reasoning before buying perception.**
2. **A labelled evaluation set that is not ours.** Real homes, not fixtures, not generated
   images — the S7.9 spike's own weakest point was that network restrictions forced it to test
   against one synthetic photo per class. Without a held-out set, "it works" is a demo.
3. **A stated accuracy floor, agreed before the numbers exist.** Precision and recall per class,
   with the failure cost named: a false negative on an egress obstruction is a blocked exit. The
   floor is written down first, or it gets negotiated downward to whatever the model achieves.
4. **A finding that still satisfies spec §2.** A detection has to produce a number, a threshold,
   a citation and an action. "Probably a bookcase (0.62)" is none of those. Any model output
   would have to land as a *suggestion the user confirms*, which is where it already lands —
   and where the confirmation step, not the model, is doing the work.
5. **Room in the scope lock.** Custom ML is excluded by the lock (product spec §4). Changing it
   needs a dated `decisions.md` entry, not an implementation.

If someone revisits this, the cheapest honest experiment is not a model at all: instrument the
hazard hunt and count how often users *correct* a scanned category. That number says whether
perception is the bottleneck. Nobody has it, which is itself the answer to why this is settled.

## 4. Where the effort goes instead

Ranked by what actually moves the finding quality, from the S10.1 and S11.3 evidence:

1. **Rules-engine correctness.** Four QA bugs, four logic defects; two were live on stock
   demo fixtures (`jagged.json` narrated an egress window as a doorway, `twostory.json` showed
   two strap-it cards for one water heater). Regression tests now pin all four plus the
   fixtures.
2. **Hazard-hunt coverage.** `secured`, portable heaters, and the water heater in the garage
   are the three highest-value facts in the model, and all three arrive by asking.
3. **Threshold fidelity.** Every cited number resolving to a real named source, imperial and
   metric consistent — `backend/corpus/validate.py` enforces it.
4. **Real-scan verification.** The engine has never run on a scan of an actual home; that gap
   is S11.10's, and it is a bigger unknown than any model's accuracy.
