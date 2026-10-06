"""S11.34 (AUD-026): checklist recurrence works through POST /score.

Timestamps are built relative to the real clock because /score reads it; the
margins (10 vs 200 days) are far from the 183-day boundary, so these cannot flake.

The monthly alarm test stopped recurring on 2026-10-05 (owner's product choice,
docs/decisions.md): it is a one-time tick, and a date an old phone stored for it
counts as done. The tests for that are at the end of this file.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app import config
from app.main import app

TEST_TOKEN = "test-token-not-a-secret"
AUTH = {"Authorization": f"Bearer {TEST_TOKEN}"}

DRILL = "practice.drill_recent"
RESCAN = "rescan.home"
ALARM_TEST = "alarm.test_monthly"


@pytest.fixture(autouse=True)
def _token_env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", TEST_TOKEN)
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


def _ago(days: float) -> str:
    return (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()


def _item(client: TestClient, home: dict, state: dict, item_id: str) -> dict:
    response = client.post(
        "/score", json={"home": home, "checklist_state": state}, headers=AUTH
    )
    assert response.status_code == 200, response.text
    return next(i for i in response.json()["checklist"] if i["id"] == item_id)


def test_old_drill_timestamp_is_not_done(client: TestClient, bungalow: dict):
    assert _item(client, bungalow, {DRILL: _ago(200)}, DRILL)["done"] is False


def test_recent_drill_timestamp_is_done(client: TestClient, bungalow: dict):
    assert _item(client, bungalow, {DRILL: _ago(10)}, DRILL)["done"] is True


def test_rescan_goes_stale_like_the_drill(client: TestClient, bungalow: dict):
    assert _item(client, bungalow, {RESCAN: _ago(200)}, RESCAN)["done"] is False
    assert _item(client, bungalow, {RESCAN: _ago(10)}, RESCAN)["done"] is True


def test_legacy_true_stays_done_until_a_timestamp_replaces_it(
    client: TestClient, bungalow: dict
):
    """STEP 0, option (a): today's app sends bare `true`; deploy must not reopen
    every existing user's drill and rescan tasks."""
    for item_id in (DRILL, RESCAN):
        item = _item(client, bungalow, {item_id: True}, item_id)
        assert item["done"] is True, item_id
        assert item["completed_at"] is None, item_id


def test_unticked_recurring_items_are_not_done(client: TestClient, bungalow: dict):
    for item_id in (DRILL, RESCAN, ALARM_TEST):
        assert _item(client, bungalow, {}, item_id)["done"] is False
        assert _item(client, bungalow, {item_id: False}, item_id)["done"] is False


@pytest.mark.parametrize("bad", ["yesterday", "", "2026-13-45T00:00:00Z", "true"])
def test_malformed_timestamp_is_422(client: TestClient, bungalow: dict, bad: str):
    response = client.post(
        "/score", json={"home": bungalow, "checklist_state": {DRILL: bad}}, headers=AUTH
    )
    assert response.status_code == 422
    assert DRILL in response.text


def test_response_exposes_recurrence_and_the_completion_time_used(
    client: TestClient, bungalow: dict
):
    stamp = _ago(10)
    drill = _item(client, bungalow, {DRILL: stamp}, DRILL)
    rescan = _item(client, bungalow, {RESCAN: stamp}, RESCAN)
    assert drill["recurrence_days"] == 183
    assert rescan["recurrence_days"] == 183
    assert datetime.fromisoformat(drill["completed_at"]) == datetime.fromisoformat(stamp)


def test_non_recurring_items_have_no_recurrence(client: TestClient, bungalow: dict):
    item = _item(client, bungalow, {}, "alarm.replace_10y")
    assert item["recurrence_days"] is None
    assert item["completed_at"] is None


def test_naive_and_zulu_timestamps_are_read_as_utc(client: TestClient, bungalow: dict):
    naive = (datetime.now(timezone.utc) - timedelta(days=10)).replace(tzinfo=None)
    zulu = (datetime.now(timezone.utc) - timedelta(days=10)).strftime("%Y-%m-%dT%H:%M:%SZ")
    assert _item(client, bungalow, {DRILL: naive.isoformat()}, DRILL)["done"] is True
    assert _item(client, bungalow, {DRILL: zulu}, DRILL)["done"] is True


def test_bool_only_requests_behave_as_before(client: TestClient, bungalow: dict):
    done = _item(client, bungalow, {"practice.meeting_point": True}, "practice.meeting_point")
    assert done["done"] is True


def test_window_edge_is_183_days_for_the_drill(client: TestClient, bungalow: dict):
    """Just past 183 days is stale, just under is done (boundary pin; not a mutation
    target for `.days` vs timedelta, which agree for non-negative ages)."""
    assert _item(client, bungalow, {DRILL: _ago(183.5)}, DRILL)["done"] is False
    assert _item(client, bungalow, {DRILL: _ago(182.5)}, DRILL)["done"] is True


def test_far_future_timestamp_is_not_done_but_small_skew_is(
    client: TestClient, bungalow: dict
):
    future = (datetime.now(timezone.utc) + timedelta(days=2000)).isoformat()
    skewed = (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat()
    assert _item(client, bungalow, {DRILL: future}, DRILL)["done"] is False
    assert _item(client, bungalow, {DRILL: skewed}, DRILL)["done"] is True


def test_naive_stamp_near_the_edge_is_read_as_utc(client: TestClient, bungalow: dict):
    """A naive stamp 182.5 days old is done only if read as UTC; a zone shift of a
    day or more would flip it, so this fails on a wrong interpretation."""
    naive = (datetime.now(timezone.utc) - timedelta(days=182.5)).replace(tzinfo=None)
    assert _item(client, bungalow, {DRILL: naive.isoformat()}, DRILL)["done"] is True


def test_offset_timestamp_is_reported_in_utc(client: TestClient, bungalow: dict):
    moment = datetime.now(timezone.utc) - timedelta(days=5)
    plus5 = moment.astimezone(timezone(timedelta(hours=5))).isoformat()
    item = _item(client, bungalow, {DRILL: plus5}, DRILL)
    assert item["completed_at"].endswith(("+00:00", "Z"))
    assert datetime.fromisoformat(item["completed_at"]) == moment.replace(microsecond=moment.microsecond)


def test_integer_flags_are_accepted_or_rejected_as_before(client: TestClient, bungalow: dict):
    ok = client.post("/score", json={"home": bungalow, "checklist_state": {DRILL: 1}}, headers=AUTH)
    bad = client.post("/score", json={"home": bungalow, "checklist_state": {DRILL: 2}}, headers=AUTH)
    assert ok.status_code == 200
    assert bad.status_code == 422


def test_timestamp_on_a_non_recurring_item_is_ignored(client: TestClient, bungalow: dict):
    item = _item(client, bungalow, {"alarm.replace_10y": _ago(1)}, "alarm.replace_10y")
    assert item["done"] is False


# ---------------------------------------------------------------------------
# The monthly alarm test is a one-time tick (owner, 2026-10-05)
# ---------------------------------------------------------------------------


def test_only_the_drill_and_the_rescan_recur(client: TestClient, bungalow: dict):
    response = client.post("/score", json={"home": bungalow}, headers=AUTH)
    recurring = {i["id"] for i in response.json()["checklist"] if i["recurrence_days"]}
    assert recurring == {DRILL, RESCAN}


def test_alarm_test_is_a_one_time_tick(client: TestClient, bungalow: dict):
    item = _item(client, bungalow, {ALARM_TEST: True}, ALARM_TEST)
    assert item["done"] is True
    assert item["recurrence_days"] is None
    assert item["completed_at"] is None
    assert _item(client, bungalow, {}, ALARM_TEST)["done"] is False
    assert _item(client, bungalow, {ALARM_TEST: False}, ALARM_TEST)["done"] is False


@pytest.mark.parametrize(
    "stored",
    [
        "2026-10-04T12:00:00Z",  # what S11.35 phones send
        "2020-01-01T00:00:00Z",  # a date years old never lapses
        "2999-01-01T00:00:00Z",  # a far-future clock is still a tick
        "not a date",  # any string: never an error for this item
        "",
    ],
)
def test_an_old_phones_stored_date_counts_as_done(
    client: TestClient, bungalow: dict, stored: str
):
    item = _item(client, bungalow, {ALARM_TEST: stored}, ALARM_TEST)
    assert item["done"] is True
    assert item["completed_at"] is None


def test_a_lapsed_alarm_test_never_lowers_the_score(client: TestClient, bungalow: dict):
    """The old rule: a date over 30 days old reopened the item and cost points.
    Now an old date scores exactly like a fresh tick or a bare true."""

    def total(state: dict) -> float:
        response = client.post(
            "/score", json={"home": bungalow, "checklist_state": state}, headers=AUTH
        )
        assert response.status_code == 200, response.text
        return response.json()["score"]

    ticked = total({ALARM_TEST: True})
    assert total({ALARM_TEST: _ago(400)}) == ticked
    assert total({ALARM_TEST: _ago(10)}) == ticked
    assert total({}) < ticked


def test_strings_on_other_items_are_still_checked(client: TestClient, bungalow: dict):
    """The any-string rule is for the alarm test only; the drill still gets a 422."""
    response = client.post(
        "/score",
        json={"home": bungalow, "checklist_state": {ALARM_TEST: "x", DRILL: "x"}},
        headers=AUTH,
    )
    assert response.status_code == 422
    # The error names the drill; the alarm test appears only in the echoed input.
    assert f"checklist_state[{DRILL!r}]" in response.text
    assert f"checklist_state[{ALARM_TEST!r}]" not in response.text
