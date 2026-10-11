# Scan quality fixes — sofa/bed findings, tight squeezes, room stitching

- **Who:** Anish (with Claude Code)
- **Date(s):** 2026-10-11
- **Status when I stopped:** merged to `main`; backend needs a Render redeploy; not yet checked on a rescan.

## What happened
From the owner's screenshot of a real scan ("Blocked doorway: the bed blocks the way to 'op-…' … move it 0.05 m … 0.51 m"):
- The cards were about egress windows (0.51 m is the window width), with a bed under the window. Furniture below the sill no longer blocks a window.
- 0.05 m is scan noise: scanned furniture now gets 0.05 m per side benefit of the doubt (real shortfalls still flagged — tested both ways).
- Shared doors are probed at the probing room's own wall, not the host's (a wall-thickness away).
- `object_hazards._obb_corners` rotated boxes the wrong way (mirror at any non-90° angle). Fixed, with a test against the nav grid.
- Cards name "the door"/"the window", not an internal id; title "Blocked way out".
- Converter: one floor axis, jog removal, room stitching (`backend/app/convert/stitch.py`).
- Tried and rejected: a wider "reached the doorway" radius — it made real squeezes vanish.

Gate 2026-10-11: backend 1287 passed / 1 skipped; corpus valid; typecheck 4/4.

## Next steps
Redeploy Render, rescan the same rooms, confirm the window cards are gone and rooms meet. Tune stitch tolerances on real exports.
