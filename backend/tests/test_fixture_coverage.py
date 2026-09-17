"""The bundled fixtures must cover both sides of the schema's optional branches.

`schema/fixtures/` is the project-wide test bed — the rule in
`.claude/rules/paths/schema.md` is "don't invent parallel test homes", which only
works if the shared set actually exercises the fields. It did not: as of
2026-09-16 **no** fixture carried `meta.last_scanned`, **no** profile carried
`hearing_impaired` or `vision_impaired` (two schema-2.0 additions with real
consumers and zero fixture coverage), and only `twostory` had a household.

These tests pin the seeding decided in that pass so it cannot drain away again
one convenient edit at a time. They assert BOTH sides of each branch: a field
present nowhere is untested, and a field present everywhere means the "absent"
path is untested, which is how `meta.last_scanned` ended up with an iOS rescan
prompt no fixture could trigger.
"""

from __future__ import annotations

import pytest

from app.models import HomeModel, ProfileTag
from tests.conftest import load_fixture

CORE_FIXTURES = ("bungalow.json", "apartment.json", "twostory.json", "jagged.json")


def _homes() -> dict[str, HomeModel]:
    return {name: HomeModel.model_validate(load_fixture(name)) for name in CORE_FIXTURES}


@pytest.mark.parametrize("name", CORE_FIXTURES)
def test_every_core_fixture_still_validates(name: str) -> None:
    HomeModel.model_validate(load_fixture(name))


def test_last_scanned_is_covered_on_both_sides() -> None:
    """Consumed by the iOS rescan prompt, the PDF and the responder snapshot. A
    home that has never been scanned is just as real as one that has, so both
    must exist in the test bed."""
    homes = _homes()
    scanned = {n for n, h in homes.items() if h.meta.last_scanned is not None}
    assert scanned, "no fixture carries meta.last_scanned"
    assert set(homes) - scanned, "every fixture is scanned; the never-scanned path is untested"


def test_the_sensory_profile_tags_are_covered() -> None:
    """`hearing_impaired` drives the strobe/bed-shaker checklist item and,
    deliberately, zero routing constraints — so a fixture carrying it is the only
    thing that proves the routing half really is unaffected end to end."""
    seen = {tag for home in _homes().values() for p in home.profiles for tag in p.tags}
    for tag in (ProfileTag.hearing_impaired, ProfileTag.vision_impaired):
        assert tag in seen, f"no fixture profile carries {tag.value}"


def test_every_profile_tag_appears_in_at_least_one_fixture() -> None:
    """The guard that keeps this file honest as the enum grows: a tag added
    without fixture coverage fails here rather than shipping untested."""
    seen = {tag for home in _homes().values() for p in home.profiles for tag in p.tags}
    missing = sorted(t.value for t in ProfileTag if t not in seen)
    assert not missing, f"profile tags with no fixture coverage: {missing}"


def test_household_is_covered_on_both_sides() -> None:
    homes = _homes()
    with_household = {n for n, h in homes.items() if h.household is not None}
    assert len(with_household) >= 2, "household is too thinly seeded to compare shapes"
    assert set(homes) - with_household, "no fixture exercises the absent-household path"


def test_both_tenures_appear() -> None:
    tenures = {h.household.tenure for h in _homes().values() if h.household}
    assert {"rent", "own"} <= {t.value if t else None for t in tenures}


def test_a_mounted_object_exists_somewhere() -> None:
    """`mounted` decides whether an object erodes walkable floor (see
    `test_obstacles.py`). Without one in the test bed that branch is reachable
    only by a test constructing its own object."""
    mounted = [
        obj.id
        for home in _homes().values()
        for floor in home.floors
        for obj in floor.objects
        if obj.mounted
    ]
    assert mounted, "no fixture carries a mounted object"
