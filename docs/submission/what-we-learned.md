# What we learned

_Draft for the submission form's "What did you learn while participating in the CAC? What was your biggest
takeaway?" question, 2026-10-05 (S11.51). Each point names where the evidence is, so a teammate can check it before
pasting. The form answer is the short version at the bottom._

## 1. Talk to the people who do the job before you decide who it is for

Early on we described our home maps as "pre-incident intelligence" that could help firefighters responding to a
house. Then we showed the idea to a working firefighter. He told us that in a working fire he cannot see his own hand, that he moves by touch and sound, and that
he would not trust a stored floor plan after a family remodels. He said it fit prevention and public education
instead. So we changed the product: it is now a readiness and prevention app for
families, the home's scan age is shown wherever the model is shared, and sharing with the fire department is an
opt-in snapshot, not something a department is expected to act on.
_Evidence: `docs/playbook/01-product-spec.md` §2; the earlier framing is in tag `archive/playbook-v1`,
`docs/playbook/06-pivot-intro.md`._

## 2. A scan is a first draft, and test data you made yourself cannot prove you right

Apple's RoomPlan gets most of a house right, but not all of it, so we built a real 3D editor to fix the rest. We
also learned that our early test homes were built from the same assumptions as our scan converter, so they agreed
with it by design. Only a real scan could prove the converter wrong. When we finally scanned a friend's house on
2026-09-08, it converted correctly the first time, but we could not have known that from our own test files.
_Evidence: `docs/tracker/field-test-lidar.md`._

## 3. Do not invent precision you do not have

Fire safety has building-code numbers, such as how big a bedroom window must be to climb out of. Earthquake and
tornado readiness mostly do not. One early tornado rule we wrote told the people in 4 of our 5 test homes to leave the
house during a warning, which is the opposite of the guidance in our own sources. We deleted it. Now the app labels
fire as "Code-quantified" and earthquake and tornado as "Guidance-based", and we never make up a number to fill a gap.
_Evidence: comment in `backend/app/routing/perils/tornado.py`; `escape_plan/Readiness/ScoreBasisLabel.swift`._

## 4. Keep the AI away from the parts that must be right

Escape routes come from a routing engine we wrote, which gives the same answer every time. The AI only explains and
answers questions, and our server rejects safety advice that does not cite a real source. That choice was tested in a
way we did not plan: our AI account ran out of credits, and the routes, fire simulation, score and checklist kept
working because none of them depend on the AI. (The citation check is verified in our tests with a stand-in for the
AI, not yet against the live model.)
_Evidence: `backend/app/routing/`, `backend/tests/test_chat.py`, BLOCKERS §1._

## 5. "The code exists" is not the same as "it works"

Our task tracker more than once said something was done when it was not, and a merge that looked clean once combined
a flipped rotation with tests written for the old direction. A merge on 2026-09-19 broke the backend, and Render
tried to deploy it anyway (the deploy failed). We learned to record a result only after running it ourselves, to write tests whose right answer we know in
advance (a 90-degree rotation test cannot tell left from right; an odd angle can), and to deploy only after the
automated checks pass (set up in `render.yaml`; the Render dashboard setting is still to be confirmed).
_Evidence: `CLAUDE.md` "Traps"; `.claude/rules/paths/editorcore.md`; BLOCKERS "Out-of-band 2026-09-19";
`render.yaml` `autoDeployTrigger: checksPass`._

## 6. Cutting is a feature

We cut an augmented-reality walk-through because it had never been tested on a real iPhone. We cut photo-based object
recognition after a test showed only 1 of 5 target objects was usable. We switched off accounts and cloud sync
to keep the demo to one story; the app works without them. Each cut made the rest more reliable to show.
_Evidence: `docs/demo/feature-inventory.md`; `docs/tracker/notes/2026-09-10-s7-9-vision-spike.md`._

## 7. Working with AI coding tools takes more checking, not less

We used AI coding agents (Claude Code and Google Antigravity) for a large share of the code; all of it is disclosed in
`docs/tools-used.md`. What worked was writing a clear plan for each work session, limiting which files each session
could touch, and checking every claim with tests and separate review steps. The AI often wrote something that looked
right and was not, and the tracker and tests are how we caught it.

## Short answer for the form

_About 120 words. A team member should read it and change anything that does not match their own experience._

> Our biggest lesson came from a firefighter. We thought our home maps could help firefighters responding to a house;
> he told us that in a real fire he cannot see his hand and would not trust an old floor plan, and that the idea fits prevention and
> education. We rebuilt the app around helping families prepare. We also learned not to invent precision: fire safety
> has building-code numbers, but earthquake and tornado readiness mostly do not, so the app labels them as
> guidance-based. And we learned to keep AI away from the parts that must be right. Our own engine plans every escape
> route, and when our AI account ran out of credits, everything except the AI features kept working.
