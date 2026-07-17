"""Compact, token-cheap text summaries of HomeModel / RoutePlan / Profile for
the S3.3 chat system prompt (pure functions, no I/O — mirrors the
`app.convert`/`app.routing` pattern of no side effects).

Deliberately NOT a full `model_dump_json()` dump: the chat system prompt is
rebuilt every turn (stateless server), so a full HomeModel dump would burn
tokens on geometry the model never needs to answer "is my kid's room safe?".
"""

from __future__ import annotations

from app.models import EXTERIOR_ID, HomeModel, Profile
from app.routing.plan import RoutePlan


def summarize_home(home: HomeModel) -> str:
    """One line per floor, one line per room, exterior exits, stairs."""
    lines = [f'Home: "{home.name}" (schema {home.schema_version}, {len(home.floors)} floor(s))']
    for floor in sorted(home.floors, key=lambda f: f.level):
        lines.append(f'Floor "{floor.name}" (level {floor.level}, id={floor.id}):')
        for room in floor.rooms:
            lines.append(f"  - room \"{room.name}\" ({room.type.value}), id={room.id}")
        exits = [op for op in floor.openings if op.is_exit]
        if exits:
            for op in exits:
                interior_room = next(r for r in op.room_ids if r != EXTERIOR_ID)
                lines.append(
                    f"  exit: {op.kind.value} \"{op.id}\" from room {interior_room} "
                    f"to outside"
                )
    for st in home.stairs:
        lines.append(
            f'Stairs "{st.id}": connects room {st.from_.room_id} (floor '
            f"{st.from_.floor_id}) to room {st.to.room_id} (floor {st.to.floor_id})"
        )
    return "\n".join(lines)


def summarize_route_plan(plan: RoutePlan) -> str:
    """Per-room primary/secondary route summary plus findings and bottlenecks."""
    lines = [f'Computed escape plan for "{plan.home_name}":']
    for room in plan.rooms:
        parts = [f'  - "{room.room_name}" (id={room.room_id}):']
        if room.primary:
            parts.append(
                f"primary route {room.primary.length_m:.1f}m via exit "
                f"{room.primary.exit_id}"
                + (" (stairs)" if room.primary.uses_stairs else "")
                + (" (window)" if room.primary.uses_window else "")
            )
        else:
            parts.append("NO PRIMARY ROUTE")
        if room.secondary:
            parts.append(
                f"; secondary route {room.secondary.length_m:.1f}m via exit "
                f"{room.secondary.exit_id}"
                + (" (stairs)" if room.secondary.uses_stairs else "")
                + (" (window)" if room.secondary.uses_window else "")
            )
        else:
            parts.append("; no secondary route")
        lines.append(" ".join(parts))
        for finding in room.findings:
            lines.append(f"    FINDING [{finding.kind}]: {finding.detail}")
    if plan.bottlenecks:
        lines.append("Bottlenecks (removing these strands rooms from every exit):")
        for b in plan.bottlenecks:
            lines.append(f"  - opening {b.opening_id} strands: {', '.join(b.disconnected_room_ids)}")
    return "\n".join(lines)


def summarize_profiles(profiles: list[Profile], home: HomeModel) -> str:
    """Profile name, tags, and bedroom location (floor + room name) per profile."""
    if not profiles:
        return "No family profiles configured yet."
    room_by_id = {r.id: (r, floor) for floor in home.floors for r in floor.rooms}
    lines = ["Family profiles:"]
    for p in profiles:
        located = room_by_id.get(p.bedroom_room_id)
        where = (
            f'bedroom "{located[0].name}" on floor "{located[1].name}"'
            if located
            else f"bedroom room id {p.bedroom_room_id} (not found in home)"
        )
        tags = ", ".join(t.value for t in p.tags) if p.tags else "none"
        lines.append(f'  - {p.name}: tags=[{tags}], {where}')
    return "\n".join(lines)
