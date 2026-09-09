"""Deterministic checklist generation (pure; no I/O, no AI).

Items come from four deterministic sources — the HomeModel itself (smoke-alarm
placement per the corpus, shutoff presence, furniture securement), the routing
engine's findings (per-peril: fire, earthquake, tornado), the S3.2 agent's
findings, and household facts (tenure, equipment, profile tags) — plus fixed
practice and readiness items. Every item id is stable for a given (home, facts,
findings) so a done-state persisted on the home document survives recomputation.

Grounded AI recommendations are appended separately (app.scoring.recommend) and
are always non-scoring: the AI advises, it never moves the number.

S6.7 NOTE: New categories (shutoffs, safe_room, mitigation, supply_kit, alerts)
are all non-scoring in this session. S6.7 owns score reweighting and will need
to decide which of these categories earn points.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional, Sequence

from pydantic import BaseModel, ConfigDict, Field

from app.models import (
    Equipment,
    HomeModel,
    OpeningKind,
    ProfileTag,
    RoomType,
    SafetyPointKind,
)
from app.routing.egress import EgressThresholds, check_egress
from app.routing.plan import RoutePlan, RoomRoutePlan
from app.scoring.findings import Finding

ItemCategory = Literal[
    "smoke_alarm",
    "practice",
    "routes",
    "egress",
    "agent_finding",
    "recommendation",
    # S6.4 additions:
    "shutoffs",
    "safe_room",
    "mitigation",
    "supply_kit",
    "alerts",
]

HazardTag = Literal["fire", "earthquake", "severe_weather", "general"]

#: The two scoring components whose points are earned by *checking boxes*
#: (as opposed to fixing the model). See docs/preparedness-score-weights.md.
SMOKE_ALARM_COMPONENT = "smoke_alarms"
PRACTICE_COMPONENT = "practice"

ChecklistState = dict[str, bool | str]
"""item id -> done (bool) or ISO timestamp (str) for recurring items.
Persisted on the home document by the iOS app (S2.4).

For recurring items, the value may be an ISO 8601 timestamp string recording
when the item was last completed. The done state is then computed by comparing
that timestamp against the item's recurrence_days. A plain `True` is always
treated as "done at an unknown time" — fresh for non-recurring items, stale
for recurring ones (conservative: forces re-completion).
"""


class ChecklistItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    category: ItemCategory
    hazard: HazardTag
    title: str
    detail: str
    why: str = Field(
        default="",
        description="One-line corpus-grounded justification shown under the item.",
    )
    done: bool = False
    source_citation: Optional[str] = Field(
        default=None,
        description="Corpus source id backing this item, when it makes a safety claim.",
    )
    scoring: bool = Field(
        description="True if checking this box moves the score by points_if_done."
    )
    component: Optional[str] = Field(
        default=None, description="Score component this item contributes to, if any."
    )
    severity: Literal["info", "low", "med", "high"] = "info"
    recurrence_days: Optional[int] = Field(
        default=None,
        description=(
            "If set, the item re-opens this many days after completion. "
            "ENGINEERING CHOICE for intervals not specified by the corpus."
        ),
    )


# ---------------------------------------------------------------------------
# Recurrence helper
# ---------------------------------------------------------------------------

def _is_done(
    item_id: str,
    state: ChecklistState,
    recurrence_days: int | None,
    now: datetime | None,
) -> bool:
    """Determine whether an item is currently done, respecting recurrence."""
    raw = state.get(item_id)
    if not raw:
        return False
    if recurrence_days is None:
        # Non-recurring: any truthy value = done.
        return bool(raw)
    # Recurring item.
    if now is None:
        # No clock provided — cannot evaluate staleness. Treat any truthy
        # value as done (backward compatible with callers that don't pass now).
        return bool(raw)
    if isinstance(raw, str):
        try:
            completed_at = datetime.fromisoformat(raw)
            elapsed = (now - completed_at).days
            return elapsed < recurrence_days
        except (ValueError, TypeError):
            return False
    # bool True on a recurring item with a clock = done at unknown time → stale.
    return False


# ---------------------------------------------------------------------------
# Existing generators (extended with hazard tags)
# ---------------------------------------------------------------------------


def _bedrooms(home: HomeModel) -> list[tuple[str, str, str]]:
    """(floor_id, room_id, room_name) for every bedroom, in document order."""
    return [
        (floor.id, room.id, room.name)
        for floor in home.floors
        for room in floor.rooms
        if room.type == RoomType.bedroom
    ]


def smoke_alarm_items(home: HomeModel, state: ChecklistState) -> list[ChecklistItem]:
    """Alarm placement + maintenance items, exactly as corpus/smoke-alarms-usfa.md
    prescribes: one per bedroom, one outside each sleeping area, one per level,
    plus the monthly test and the 10-year replacement."""
    bedrooms = _bedrooms(home)
    floors_with_bedrooms = {floor_id for floor_id, _, _ in bedrooms}
    items: list[ChecklistItem] = []

    def add(item_id: str, title: str, detail: str) -> None:
        items.append(
            ChecklistItem(
                id=item_id,
                category="smoke_alarm",
                hazard="fire",
                title=title,
                detail=detail,
                why="Working smoke alarms cut the home-fire death rate by ~55%. [cite: nfpa-smoke-alarms-report]",
                done=state.get(item_id, False) is True,
                source_citation="usfa-smoke-alarms",
                scoring=True,
                component=SMOKE_ALARM_COMPONENT,
            )
        )

    for _, room_id, room_name in bedrooms:
        add(
            f"alarm.bedroom.{room_id}",
            f"Smoke alarm inside {room_name}",
            "A working smoke alarm belongs inside every room used for sleeping.",
        )
    for floor in home.floors:
        if floor.id in floors_with_bedrooms:
            add(
                f"alarm.sleeping_area.{floor.id}",
                f"Smoke alarm outside the sleeping area on {floor.name}",
                "An alarm goes outside each separate sleeping area — the hallway "
                "serving the bedrooms.",
            )
    for floor in home.floors:
        add(
            f"alarm.level.{floor.id}",
            f"Smoke alarm on {floor.name}",
            "Every level of the home needs at least one smoke alarm.",
        )
    add(
        "alarm.test_monthly",
        "Test every smoke alarm this month",
        "Press the test button on every alarm once a month.",
    )
    add(
        "alarm.replace_10y",
        "Confirm no alarm is over 10 years old",
        "Replace every smoke alarm 10 years from its manufacture date.",
    )
    return items


def practice_items(
    state: ChecklistState, now: datetime | None = None
) -> list[ChecklistItem]:
    """The two fixed plan-practice items, plus the rescan item. Drill mode (S4.2)
    checks `practice.drill_recent` when a drill completes."""
    drill_recurrence = 183  # ENGINEERING CHOICE: ~6 months, twice-a-year cadence
    return [
        ChecklistItem(
            id="practice.meeting_point",
            category="practice",
            hazard="general",
            title="Pick an outside meeting place",
            detail="Choose one safe spot a distance from the home — a mailbox, a "
            "tree, a neighbor's porch — where everyone gathers after escaping.",
            why="A pre-agreed meeting point prevents re-entry to search for someone already safe. [cite: nfpa-escape-planning]",
            done=state.get("practice.meeting_point", False) is True,
            source_citation="nfpa-escape-planning",
            scoring=True,
            component=PRACTICE_COMPONENT,
        ),
        ChecklistItem(
            id="practice.drill_recent",
            category="practice",
            hazard="general",
            title="Practice the plan (twice a year)",
            detail="Run the drill with everyone in the household; the Red Cross "
            "benchmark is everyone at the meeting place in under two minutes.",
            why="Only ~26% of families have practiced their escape plan. [cite: redcross-escape-fact-sheet]",
            done=_is_done("practice.drill_recent", state, drill_recurrence, now),
            source_citation="nfpa-escape-planning",
            # Bug B fix (S6.7 merge, 2026-09-07): a lapsed/never-done drill must
            # flag staleness, never lower the score — same non-punitive rule as
            # rescan.home. See docs/preparedness-score-weights.md.
            scoring=False,
            component=PRACTICE_COMPONENT,
            recurrence_days=drill_recurrence,
        ),
        ChecklistItem(
            id="rescan.home",
            category="practice",
            hazard="general",
            title="Rescan your home to keep the model current",
            detail="Furniture moves, renovations happen. Rescan every ~6 months "
            "so the routes and checklist stay accurate.",
            why="Routes are computed from the scan; an outdated model produces outdated advice.",
            done=_is_done("rescan.home", state, drill_recurrence, now),
            source_citation=None,
            scoring=False,
            recurrence_days=drill_recurrence,
        ),
    ]


def route_items(
    plan: RoutePlan, state: ChecklistState
) -> list[ChecklistItem]:
    """Items mirroring the routing engine's structured findings.

    Non-scoring: these are fixed by changing the home (adding an egress window,
    unblocking a route) and re-running the engine, which moves the routes
    components on its own. Checking the box must never double-count.
    """
    hazard = _peril_to_hazard(plan.peril)
    items: list[ChecklistItem] = []
    for room in plan.rooms:
        for finding in room.findings:
            if finding.kind == "no_secondary_egress":
                title = f"Add a second way out of {room.room_name}"
                item_id = f"routes.{finding.kind}.{room.room_id}"
                citation = "nfpa-escape-planning"
                why = "Two ways out is NFPA's core escape-planning rule. [cite: nfpa-escape-planning]"
            elif finding.kind == "blocked_opening":
                blocked = "-".join(finding.object_ids) or "obstruction"
                item_id = f"routes.{finding.kind}.{room.room_id}.{blocked}"
                title = f"Clear the way out of {room.room_name}"
                citation = "usfa-escape-plans"
                why = "A blocked exit doubles the time to escape. [cite: usfa-escape-plans]"
            elif finding.kind == "narrows_route":
                squeezed = "-".join(finding.object_ids) or "obstruction"
                item_id = f"routes.{finding.kind}.{room.room_id}.{squeezed}"
                title = f"Widen the way out of {room.room_name}"
                citation = "usfa-escape-plans"
                why = "A tight exit slows evacuation, especially in the dark. [cite: usfa-escape-plans]"
            else:
                title = f"{room.room_name} has no usable way out"
                item_id = f"routes.{finding.kind}.{room.room_id}"
                citation = "nfpa-escape-planning"
                why = "Every room needs a viable escape route. [cite: nfpa-escape-planning]"
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="routes",
                    hazard=hazard,
                    title=title,
                    detail=finding.detail,
                    why=why,
                    done=state.get(item_id, False) is True,
                    source_citation=citation,
                    scoring=False,
                )
            )
    return items


def egress_window_items(
    home: HomeModel, thresholds: EgressThresholds, state: ChecklistState
) -> list[ChecklistItem]:
    """Bedroom escape windows that fail IRC R310, checked deterministically."""
    items: list[ChecklistItem] = []
    for floor in home.floors:
        bedrooms = {r.id: r for r in floor.rooms if r.type == RoomType.bedroom}
        grade_floor = floor.level <= 0
        for opening in floor.openings:
            if opening.kind != OpeningKind.window:
                continue
            served = [rid for rid in opening.room_ids if rid in bedrooms]
            if not served:
                continue
            assessment = check_egress(opening, thresholds, grade_floor=grade_floor)
            if assessment.viable:
                continue
            room = bedrooms[served[0]]
            item_id = f"egress.window.{opening.id}"
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="egress",
                    hazard="fire",
                    title=f"Escape window in {room.name} is too small to climb out of",
                    detail=(
                        "An emergency escape window in a sleeping room has to be "
                        "big enough to climb through: "
                        + "; ".join(assessment.reasons)
                        + "."
                    ),
                    why="IRC R310 requires sleeping rooms to have an emergency escape opening. [cite: irc-2021-r310]",
                    done=state.get(item_id, False) is True,
                    source_citation="irc-2021-r310",
                    scoring=False,
                )
            )
    return items


def finding_items(
    findings: Sequence[Finding], state: ChecklistState
) -> list[ChecklistItem]:
    """Items from the S3.2 agent's findings."""
    items: list[ChecklistItem] = []
    for index, finding in enumerate(findings):
        item_id = (
            f"agent_finding.{finding.id}" if finding.id else f"agent_finding.{index}"
        )
        items.append(
            ChecklistItem(
                id=item_id,
                category="agent_finding",
                hazard="general",
                title=finding.finding,
                detail=finding.recommendation,
                why=f"[cite: {finding.citation}]" if finding.citation else "",
                done=state.get(item_id, False) is True,
                source_citation=finding.citation,
                scoring=False,
                severity=finding.severity,
            )
        )
    return items


# ---------------------------------------------------------------------------
# S6.4 new generators
# ---------------------------------------------------------------------------

def _peril_to_hazard(peril: str) -> HazardTag:
    """Map a RoutePlan peril string to a HazardTag."""
    return {
        "fire": "fire",
        "tornado": "severe_weather",
        "earthquake": "earthquake",
    }.get(peril, "general")


def shutoff_items(home: HomeModel, state: ChecklistState) -> list[ChecklistItem]:
    """Items for floors missing gas shutoff or electrical panel safety points."""
    items: list[ChecklistItem] = []
    for floor in home.floors:
        sp_kinds = {sp.kind for sp in floor.safety_points}
        if SafetyPointKind.gas_shutoff not in sp_kinds:
            item_id = f"shutoffs.gas.{floor.id}"
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="shutoffs",
                    hazard="earthquake",
                    title=f"Locate and tag your gas shutoff valve on {floor.name}",
                    detail=(
                        "Know where your gas shutoff is and keep a wrench nearby. "
                        "Only shut off if you suspect a leak."
                    ),
                    why="A ruptured gas line after shaking is a secondary fire/explosion hazard. [cite: fema-earthquake]",
                    done=state.get(item_id, False) is True,
                    source_citation="fema-earthquake",
                    scoring=False,
                )
            )
        if SafetyPointKind.electrical_panel not in sp_kinds:
            item_id = f"shutoffs.electrical.{floor.id}"
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="shutoffs",
                    hazard="general",
                    title=f"Locate and tag your electrical panel on {floor.name}",
                    detail=(
                        "Know where your electrical panel is so you can shut off "
                        "power in an emergency."
                    ),
                    why="Post-disaster electrical damage can cause fires. [cite: fema-earthquake]",
                    done=state.get(item_id, False) is True,
                    source_citation="fema-earthquake",
                    scoring=False,
                )
            )
    return items


def safe_room_items(
    tornado_plan: RoutePlan | None,
    state: ChecklistState,
) -> list[ChecklistItem]:
    """Items derived from the tornado routing plan."""
    if tornado_plan is None:
        return []
    items: list[ChecklistItem] = []
    seen_no_viable = False
    has_shelter = False
    for room in tornado_plan.rooms:
        for finding in room.findings:
            if finding.kind == "no_viable_safe_room" and not seen_no_viable:
                seen_no_viable = True
                item_id = "safe_room.nearby_shelter"
                items.append(
                    ChecklistItem(
                        id=item_id,
                        category="safe_room",
                        hazard="severe_weather",
                        title="Identify a nearby sturdy building for tornado shelter",
                        detail=(
                            "No room in your home qualifies as a safe room. "
                            "Identify a nearby sturdy building (community shelter, "
                            "neighbor's basement) you can reach quickly."
                        ),
                        why="Mobile and manufactured homes are not safe during a tornado, whatever the wind speed. [cite: redcross-tornado]",
                        done=state.get(item_id, False) is True,
                        source_citation="redcross-tornado",
                        scoring=False,
                        severity="high",
                    )
                )
        if room.primary is not None:
            has_shelter = True

    if has_shelter and not seen_no_viable:
        item_id = "safe_room.know"
        items.append(
            ChecklistItem(
                id=item_id,
                category="safe_room",
                hazard="severe_weather",
                title="Know your tornado safe room",
                detail=(
                    "Your home's safe room has been identified by the engine. "
                    "Make sure every household member knows where to go when a "
                    "tornado warning is issued."
                ),
                why="Go to the lowest floor, most interior room, as many walls as possible between you and outside. [cite: noaa-tornado]",
                done=state.get(item_id, False) is True,
                source_citation="noaa-tornado",
                scoring=False,
            )
        )
    return items


def mitigation_items(home: HomeModel, state: ChecklistState) -> list[ChecklistItem]:
    """Earthquake mitigation items for unsecured tall/heavy objects.

    Tenure-aware: renters get adhesive-strap guidance (corpus-cited from
    shakeout-guidance); owners get wall-stud guidance.
    """
    is_renter = (
        home.household is not None and home.household.tenure is not None
        and home.household.tenure.value == "rent"
    )
    heavy_categories = {"wardrobe", "storage", "appliance"}
    items: list[ChecklistItem] = []
    for floor in home.floors:
        for obj in floor.objects:
            if obj.category.value not in heavy_categories:
                continue
            if obj.secured:
                continue
            if is_renter:
                item_id = f"mitigation.secure.{obj.id}.renter"
                title = f"Secure {obj.category.value} '{obj.id}' with earthquake-rated adhesive straps"
                detail = (
                    "Use flexible nylon straps with high-strength, earthquake-rated "
                    "adhesives — no wall drilling required."
                )
                why = "Renter-friendly furniture straps are available without drilling. [cite: shakeout-guidance]"
            else:
                item_id = f"mitigation.secure.{obj.id}"
                title = f"Secure {obj.category.value} '{obj.id}' to wall studs"
                detail = (
                    "Bolt tall or heavy furniture to wall studs. Standard drywall "
                    "anchors are not strong enough during an earthquake."
                )
                why = "Unsecured furniture is a leading cause of earthquake injuries. [cite: usgs-earthquake]"
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="mitigation",
                    hazard="earthquake",
                    title=title,
                    detail=detail,
                    why=why,
                    done=state.get(item_id, False) is True,
                    source_citation="shakeout-guidance",
                    scoring=False,
                )
            )
    return items


def supply_kit_items(state: ChecklistState) -> list[ChecklistItem]:
    """The single shared supply-kit item — tagged general, appears once."""
    item_id = "supply_kit.72h"
    return [
        ChecklistItem(
            id=item_id,
            category="supply_kit",
            hazard="general",
            title="Assemble a 72-hour emergency supply kit",
            detail=(
                "Water (one gallon per person per day for three days), food, "
                "flashlight, batteries, first-aid kit, medications, copies of "
                "important documents."
            ),
            why="You may need to shelter in place or evacuate with no access to stores. [cite: fema-earthquake]",
            done=state.get(item_id, False) is True,
            source_citation="fema-earthquake",
            scoring=False,
        )
    ]


def alert_items(home: HomeModel, state: ChecklistState) -> list[ChecklistItem]:
    """Weather alert items + hearing-impaired strobe/bed-shaker items.

    hearing_impaired produces checklist items AND ZERO routing constraints.
    This is asserted by test.
    """
    items: list[ChecklistItem] = []

    # Universal weather alert item
    item_id = "alerts.weather_radio"
    items.append(
        ChecklistItem(
            id=item_id,
            category="alerts",
            hazard="severe_weather",
            title="Ensure multiple ways to receive severe weather alerts",
            detail=(
                "NOAA Weather Radio plus phone notifications. Know the difference: "
                "Watch = conditions favorable; Warning = seek shelter immediately."
            ),
            why="Tornado warnings give minutes of lead time — receiving them is life-or-death. [cite: redcross-tornado]",
            done=state.get(item_id, False) is True,
            source_citation="redcross-tornado",
            scoring=False,
        )
    )

    # hearing_impaired profiles -> strobe/bed-shaker
    for profile in home.profiles:
        if ProfileTag.hearing_impaired in profile.tags:
            item_id = f"alerts.strobe.{profile.id}"
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="alerts",
                    hazard="general",
                    title=f"Install a bed-shaker or strobe-light alarm for {profile.name}",
                    detail=(
                        "Smoke alarms with strobe lights and bed-shaker/vibrating "
                        "accessories ensure alarms actually wake someone who is deaf "
                        "or hard of hearing. Also ensure weather alerts use visual "
                        "or vibrating notifications."
                    ),
                    why="Standard audible alarms may not wake a person who is deaf or hard of hearing. [cite: usfa-smoke-alarms]",
                    done=state.get(item_id, False) is True,
                    source_citation="usfa-smoke-alarms",
                    scoring=False,
                )
            )
    return items


def household_items(
    home: HomeModel,
    state: ChecklistState,
    fire_plan: RoutePlan | None = None,
    tornado_plan: RoutePlan | None = None,
) -> list[ChecklistItem]:
    """Items driven by household facts and profile tags.

    - mobility_limited + no_viable_route/no_viable_safe_room -> high-severity item
    - child -> accompanied-adult pairing
    - pet -> leash/carrier near exit (routing no-op, asserted by test)
    """
    items: list[ChecklistItem] = []

    # Collect rooms with no-viable findings across plans
    no_viable_rooms: set[str] = set()
    for plan in (fire_plan, tornado_plan):
        if plan is None:
            continue
        for room in plan.rooms:
            for finding in room.findings:
                if finding.kind in ("no_viable_route", "no_viable_safe_room"):
                    no_viable_rooms.add(room.room_id)

    for profile in home.profiles:
        # mobility_limited -> sleep near accessible exit
        if ProfileTag.mobility_limited in profile.tags:
            item_id = f"household.sleep_near_exit.{profile.id}"
            sev: Literal["info", "high"] = "info"
            if profile.bedroom_room_id in no_viable_rooms:
                sev = "high"
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="routes",
                    hazard="general",
                    title=f"{profile.name} should sleep near an accessible exit, ideally on the ground floor",
                    detail=(
                        "A person with mobility limitations should sleep near an "
                        "accessible exit to shorten and simplify the escape route."
                    ),
                    why="Stairs and window egress are generally not usable for a wheelchair user. [cite: usfa-disabilities]",
                    done=state.get(item_id, False) is True,
                    source_citation="usfa-disabilities",
                    scoring=False,
                    severity=sev,
                )
            )

        # child -> assign an adult
        if ProfileTag.child in profile.tags:
            item_id = f"household.child_assist.{profile.id}"
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="practice",
                    hazard="general",
                    title=f"Assign an adult to assist {profile.name} during evacuation",
                    detail=(
                        "Children may not wake to a smoke alarm. Assign a specific "
                        "adult to each young child in the plan."
                    ),
                    why="Children may not wake independently; an assigned adult ensures they escape. [cite: nfpa-escape-planning]",
                    done=state.get(item_id, False) is True,
                    source_citation="nfpa-escape-planning",
                    scoring=False,
                )
            )

        # pet -> leash/carrier
        if ProfileTag.pet in profile.tags:
            item_id = f"household.pet_evac.{profile.id}"
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="practice",
                    hazard="general",
                    title=f"Keep a leash/carrier near the exit for {profile.name}",
                    detail=(
                        "Include pets in the plan — who grabs the leash/carrier if "
                        "immediately at hand on the way out — but people escape first. "
                        "Never delay escape or re-enter for pets."
                    ),
                    why="People escape first; pets drive phrasing, never route computation. [cite: redcross-escape-plan]",
                    done=state.get(item_id, False) is True,
                    source_citation="redcross-escape-plan",
                    scoring=False,
                )
            )

    return items


def engine_finding_items(
    plans: Sequence[RoutePlan],
    state: ChecklistState,
) -> list[ChecklistItem]:
    """Checklist items derived from engine findings across all peril plans.

    Deduplicates: the same room with the same finding kind across plans
    produces one item, not N.
    """
    items: list[ChecklistItem] = []
    seen: set[str] = set()

    for plan in plans:
        hazard = _peril_to_hazard(plan.peril)
        for room in plan.rooms:
            for finding in room.findings:
                if finding.kind == "no_viable_safe_room":
                    # Handled by safe_room_items; skip duplication.
                    continue
                if finding.kind == "no_cover_in_room":
                    item_id = f"engine.no_cover.{room.room_id}"
                    if item_id in seen:
                        continue
                    seen.add(item_id)
                    items.append(
                        ChecklistItem(
                            id=item_id,
                            category="mitigation",
                            hazard="earthquake",
                            title=f"No earthquake cover in {room.room_name}",
                            detail=(
                                "Practice Drop, Cover, Hold On with arms protecting "
                                "your head and neck. Consider adding a sturdy table."
                            ),
                            why="Getting under a sturdy table is the safest position during shaking. [cite: shakeout-guidance]",
                            done=state.get(item_id, False) is True,
                            source_citation="shakeout-guidance",
                            scoring=False,
                        )
                    )
                if finding.kind == "no_viable_route":
                    item_id = f"engine.no_viable_route.{room.room_id}"
                    if item_id in seen:
                        continue
                    seen.add(item_id)
                    items.append(
                        ChecklistItem(
                            id=item_id,
                            category="routes",
                            hazard=hazard,
                            title=f"{room.room_name} has no escape route under current constraints",
                            detail=finding.detail,
                            why="A room with no viable route is a trap. [cite: nfpa-escape-planning]",
                            done=state.get(item_id, False) is True,
                            source_citation="nfpa-escape-planning",
                            scoring=False,
                            severity="high",
                        )
                    )
    return items


# ---------------------------------------------------------------------------
# Equipment pre-satisfaction
# ---------------------------------------------------------------------------

def _apply_equipment_presatisfaction(
    items: list[ChecklistItem],
    home: HomeModel,
) -> list[ChecklistItem]:
    """Mark items as done when the household declares existing equipment.

    The item STILL appears (so the user sees it was considered), but pre-set
    to done. This is the "derive first, store only when you must" principle:
    the spatial artefact (equipment exists) determines the state.
    """
    if home.household is None:
        return items
    equipment = set(home.household.existing_equipment)
    if Equipment.smoke_alarm in equipment:
        for item in items:
            if item.category == "smoke_alarm" and (
                item.id.startswith("alarm.bedroom.")
                or item.id.startswith("alarm.sleeping_area.")
                or item.id.startswith("alarm.level.")
            ):
                item.done = True
    return items


# ---------------------------------------------------------------------------
# build_checklist (the public entry point)
# ---------------------------------------------------------------------------


def build_checklist(
    home: HomeModel,
    plan: RoutePlan,
    findings: Sequence[Finding],
    state: ChecklistState,
    thresholds: Optional[EgressThresholds] = None,
    *,
    tornado_plan: Optional[RoutePlan] = None,
    earthquake_plan: Optional[RoutePlan] = None,
    now: Optional[datetime] = None,
) -> list[ChecklistItem]:
    """The full deterministic checklist, ordered scoring-items-first.

    `thresholds` is optional only for backward compatibility with callers
    predating the egress items — pass it. Without it, undersized bedroom escape
    windows are only reported when /analyze has been run.

    `tornado_plan` / `earthquake_plan` enable the S6.4 multi-peril items.
    Omitting them produces exactly the pre-S6.4 checklist (backward compat).

    `now` is the current time for evaluating recurrence. If None, recurring
    items with timestamp state are treated as stale. The generator itself
    remains pure — `now` is an explicit input, not a clock read.
    """
    all_plans: list[RoutePlan] = [plan]
    if tornado_plan is not None:
        all_plans.append(tornado_plan)
    if earthquake_plan is not None:
        all_plans.append(earthquake_plan)

    items = [
        *smoke_alarm_items(home, state),
        *practice_items(state, now),
        *route_items(plan, state),
        *(egress_window_items(home, thresholds, state) if thresholds else []),
        *finding_items(findings, state),
        # S6.4 additions:
        *shutoff_items(home, state),
        *safe_room_items(tornado_plan, state),
        *mitigation_items(home, state),
        *supply_kit_items(state),
        *alert_items(home, state),
        *household_items(home, state, plan, tornado_plan),
        *engine_finding_items(all_plans, state),
    ]

    items = _apply_equipment_presatisfaction(items, home)
    return items
