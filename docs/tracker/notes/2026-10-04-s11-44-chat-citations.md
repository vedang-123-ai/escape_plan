# S11.44 — Chat rejects safety claims that carry no citation

- **Who:** Anish (agent-run)
- **Date(s):** 2026-10-04
- **Status when I stopped:** done under stub tests and merged; the live check is owed to S11.49 (billing).

## What happened
- STEP 0 = (a): a server post-check, one corrective retry, then a fixed deferral. `/chat` still returns `{reply, citations}`.
- New `backend/app/ai/chat/claims.py`: the one definition of "safety claim" (in its docstring). `chat()` uses it,
  and so do the eval graders (`cites_every_safety_claim` in `tests/evals/graders.py`), so the two cannot drift.
  The sentence splitter moved there too, and `says_call_911_first` uses it.
- `chat()`: fabricated ids are handled as before. An uncited safety claim gets one corrective retry, inside the same
  3-call cap that S11.27's budget charges for, and only if `deadline.can_start()` (S11.29). That retry is a last chance.
  Anything that goes wrong after it ends in `UNCITED_DEFERRAL`, never a 502 or 504.
- Two eval cases added (`uncited-safety-claim`, `mixed-cited-and-uncited`), and `uncited-claim-rejected` now uses the new
  grader. The live runner's expected count is 18 (13 through chat). A service-level eval test drives every case
  graded by the new grader through `chat()`.
- Mutation checks: 30 code breaks in `service.py`/`claims.py` over three rounds. Each turned a named test red, then
  was restored by copying from a scratchpad backup (`cmp` confirmed). Some needed new probes before they went red:
  - the broad "any 911" exemption;
  - the route-narration direction rule, its hazard guard, and its going-back-in guard;
  - the first-person self-talk rule;
  - curly-apostrophe normalisation. My first `sed` mutation here never applied; redone with a regex, it went red.

## Decisions / surprises
- The grounding-auditor's key catch: before this change, an emergency reply with one uncited sentence shipped with its
  911 line. A naive retry could turn it into a 504, a 502, or a cited reply without 911. Hence the last-chance rule and
  the 911-dropped check.
- The grounding-auditor's second round: the fallback put 911 in its second sentence, which breaks rule 4, and its own
  grader `says_call_911_first` rejected it. It now leads with the 911 line, and a test asserts that.
- The first detector had holes both ways:
  - it missed curly apostrophes, "I recommend ..." and advice next to 911;
  - it blocked route narration ("go down the Hall to the front door") and sign-offs.
  Each exemption is now narrow, and the reviewers' strings are pinned as adversarial/benign probes.
- The prompt's own example was an uncited imperative. It now carries a cite, and rule 3 says route facts need no tag.
  A test checks that the example passes the rule it teaches.

## Questions for teammates
- Anish: the fallback wording is in BLOCKERS under "S11.44 findings". Say if you want it changed.

## Next steps
- S11.49 (live run): measure how often a normal question ends in the fallback, and run the two new cases.
