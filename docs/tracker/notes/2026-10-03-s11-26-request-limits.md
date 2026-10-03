# S11.26 — Request size limits and input caps on every endpoint

- **Who:** P3 (agent-run)
- **Date(s):** 2026-10-03
- **Status when I stopped:** done and merged. AUD-004's body-size half, AUD-035's input-caps half and
  AUD-024's server half are fixed. AUD-035's timeout half is untouched and still belongs to S11.29.

## What happened

New `backend/app/limits.py` holds every limit as a named constant, because S11.33 and S11.45 have to agree
with the server and the editor already mirrors the geometry bounds.

**Measured before choosing anything.** The useful question was not "how big is a fixture" (largest committed
one: 14 KB) but "how big can a request the server MUST accept be" — and the S11.25 geometry bounds already
answer that. Built a home sitting at every bound simultaneously and measured it:

| | bytes |
| --- | --- |
| maximum bounds-valid home, compact | 1,649,482 |
| maximum bounds-valid home, pretty | 1,780,354 |
| that home's `route_plan` | 273,048 |
| its `profiles`, sent again separately | 10,340 |
| **combined `/chat` worst case** | **2,063,742** |

`MAX_TOTAL_GRID_CELLS` is the bound that binds first — 200 rooms only fit if each is small. A home one byte
bigger is rejected by `HomeModel` anyway, so it never reaches the body limit.

The limits, with the headroom stated: **8 MiB default** (4.06x the combined worst case), **16 MiB `/build`**
(it has to hold a 10 MB base64 image). `/build`: description 20,000 chars, `image_b64` 10,000,000 chars,
`image_media_type` an allow-list of the four types Anthropic accepts. `/chat`: 40 messages, 8,000 chars each,
100,000 total — the total binds first, since the product would be 320,000. Every violation is 422, never
silent truncation: answering about a conversation the user did not send would look authoritative and be about
the wrong house.

The middleware is raw ASGI rather than `BaseHTTPMiddleware`, because measuring via `await request.body()`
would buffer the whole body and so do the exact thing the limit exists to prevent. A declared
`Content-Length` is compared without reading; a chunked body is counted up to `limit + 1` bytes only.

**Evidence (2026-10-03).** `backend/.venv/bin/python -m pytest backend/tests/ -m "not live"` →
**973 passed, 1 skipped, 29 deselected** (53 s). New file alone: 41 passed. `test_route_guards.py`: 31 passed.
`python3 backend/corpus/validate.py` → valid, 36 sources / 13 files / 2 threshold files / 44 tips.
Baseline before this session was 932, so +41.

## Decisions / surprises

**The audit's Anthropic image limit was wrong for our deployment.** It says "~5 MB" from memory; that is the
Amazon Bedrock and Google Cloud figure. The direct Claude API accepts **10 MB base64-encoded**, confirmed
against the official vision docs. Accepted types are jpeg/png/gif/webp — HEIC is not among them, which is the
root of AUD-024. Used 10 MB.

**I shipped a bypass of my own limit and caught it on review.** A request declaring `Content-Length: 10`
alongside `Transfer-Encoding: chunked` pushed 12,582,912 bytes through the 8,388,608 cap, because a declared
length short-circuits the counting path — so a declaration that is a lie defeats the limit outright rather
than under-counting it. My first write-up claimed h11 rejects that header pair, which would have limited the
reach to a deployment behind a permissive proxy. **That was wrong, and the security review caught it.**
Verified on the installed h11 0.16.0 with `httptools` absent (so uvicorn uses h11):
`h11._headers.normalize_and_validate` accepts the pair and keeps both headers, and
`h11._connection._body_framing` returns `("chunked", ())` at its own "Step 2: check for Transfer-Encoding
(T-E beats C-L)" before it ever reads Content-Length. Directly exploitable, no proxy needed. The lesson worth
keeping: a size limit that holds only because another layer happens to be strict is not a limit.

**Extrapolating a ratio would have misled me, in an interesting direction.** The grounding auditor rightly
noted my first headroom figure measured only the home term while `/explain` and `/chat` send
home + route_plan + profiles. On the small fixtures a `route_plan` runs **~1.9x** the home it describes, which
predicts a 5.3 MB body and an uncomfortably tight limit. Measured at the maximum it is **0.17x** — the ratio
inverts, because a maximal home is dominated by 200 room polygons and 3,200 openings while its route plan
still describes a handful of paths. Measuring the combination gave 2.06 MB and the 8 MiB limit stood. Vary
each input independently, then measure the combination.

**The allow-list does less than I first wrote.** It refuses a *correctly labelled* unsupported type. It does
not fix AUD-024's user-visible symptom, because `APIClient+Build.swift` hardcodes `image_media_type =
"image/png"` at both the struct and function defaults and `BuildFromPlanView` omits the argument — so real
HEIC camera bytes still arrive labelled PNG, pass the allow-list and the base64 decode, and still reach
Anthropic. The docstring now says so. S11.33 owns the client half.

**Routing the maximum home took 49.7 s for one peril**, against `models.py`'s claim that a maximal home
finishes a *three*-peril `/score` in under ~25 s on a 2026 Mac. Either this machine is slower or the S11.25
budget is optimistic by ~2x. BLOCKERS line; re-measure on the filming Mac before S11.11.

**`ecc:security-reviewer` does not exist in this install**, so ACCEPTANCE could not be run as written —
already a known gap logged under S11.25 findings. Substituted the `security-review` skill. It found nothing at
confidence >= 8 on the final tip, after independently confirming the `Content-Length` bypass. The
`grounding-auditor` half ran as specified: **GROUNDED**, no violation, the only `backend/app/ai/` edit being
the one field constraint the playbook permits.

## Questions for teammates

- **@P1 / @P2:** the 49.7 s measurement above. If `/score` on a maximal home really is ~50 s per peril rather
  than ~25 s for three, that is a demo risk, and the bound in `models.py` is documenting a budget it does not
  meet. Can one of you time it on the filming Mac?
- **@P2 (or whoever takes S11.37):** two client-side honesty gaps are logged in BLOCKERS — no `case 413` arm,
  and `/chat`'s 422 `detail` discarded before it reaches the user. Both are S11.37's by my reading; say so if
  you would rather they sat with S11.33/S11.45.

## Next steps

- Lane E continues at **S11.27** (AI spend ceiling), which S11.26 does not block.
- S11.29 picks up AUD-035's timeout half and reads the chat caps from this note.
- S11.33 reads `ALLOWED_IMAGE_MEDIA_TYPES` and `MAX_IMAGE_B64_CHARS` from `backend/app/limits.py`; S11.45
  reads `MAX_CHAT_MESSAGES` / `MAX_CHAT_MESSAGE_CHARS` / `MAX_CHAT_TOTAL_CHARS` from the same place.
