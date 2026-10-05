# App description

_Draft for the submission form, 2026-10-05 (S11.51). Under 250 words; the count is checked by `wc -w` on the block
below. The pitch-truth-auditor and doc-auditor runs of 2026-10-05
and what they changed are recorded in BLOCKERS "S11.51 findings"._

**Before pasting:** if the Anthropic account is still unfunded on submission day, the assistant does not answer
(the server returns an error by design), so delete the assistant paragraph. Its citation check is verified in stub
tests only, never against the live model (BLOCKERS AUD-002, AUD-030). The routing, simulation, score, checklist,
printing and sharing do not use AI and are unaffected.

---

**Escape Plan** helps a family make and practise a home escape plan before an emergency happens.

You scan your home with an iPhone's LiDAR sensor, or draw it in the app, and get a 3D model of your house. Scans
are never perfect, so the app includes a full 3D editor for adding a missing window, moving a wall or connecting
stairs.

Our own routing engine then finds a main and a backup way out of every room for each person, and warns when a room
has no backup. A child, an older relative or someone who cannot use stairs gets a route that fits them. You can start
a pretend fire in any room and watch everyone's route change around it.

The app gives a readiness score and a checklist for three hazards. Fire is checked against building-code numbers,
such as whether a bedroom window is big enough to climb out of. Earthquake and tornado are readiness guides built
from FEMA, NOAA and USGS guidance, and the app labels them that way. You can print the plan and, if you choose, send a
snapshot to your local fire department.

An AI assistant answers questions about your home. Our server only lets through safety advice that cites a
source in our library (FEMA, NFPA, the Red Cross and others). The AI never plans a route; our engine does that.

Escape Plan is for prevention and practice. It is not a tool for firefighters during a fire.
