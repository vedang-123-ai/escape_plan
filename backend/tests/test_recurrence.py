"""S11.34 (AUD-026): checklist recurrence works through POST /score.

Timestamps are built relative to the real clock because /score reads it; the
margins (10 vs 200 days, 10 vs 40 days) are far from the 183- and 30-day
boundaries, so these cannot flake.
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
    for item_id in (DRILL, RESCAN, ALARM_TEST):
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


def test_monthly_alarm_test_goes_stale_after_its_interval(
    client: TestClient, bungalow: dict
):
    fresh = _item(client, bungalow, {ALARM_TEST: _ago(10)}, ALARM_TEST)
    stale = _item(client, bungalow, {ALARM_TEST: _ago(40)}, ALARM_TEST)
    assert fresh["done"] is True
    assert stale["done"] is False


def test_stale_monthly_test_lowers_the_alarm_score(client: TestClient, bungalow: dict):
    """The monthly test is a scoring item (docs/preparedness-score-weights.md), so
    letting it lapse is visible in the number, not only on the checklist."""

    def total(state: dict) -> float:
        response = client.post(
            "/score", json={"home": bungalow, "checklist_state": state}, headers=AUTH
        )
        return response.json()["score"]

    assert total({ALARM_TEST: _ago(10)}) > total({ALARM_TEST: _ago(40)})


def test_response_exposes_recurrence_and_the_completion_time_used(
    client: TestClient, bungalow: dict
):
    stamp = _ago(10)
    drill = _item(client, bungalow, {DRILL: stamp}, DRILL)
    alarm = _item(client, bungalow, {ALARM_TEST: stamp}, ALARM_TEST)
    assert drill["recurrence_days"] == 183
    assert alarm["recurrence_days"] == 30
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


def test_window_edge_is_30_days_for_the_monthly_test(client: TestClient, bungalow: dict):
    """Just past 30 days is stale, just under is done (boundary pin; not a mutation
    target for `.days` vs timedelta, which agree for non-negative ages)."""
    assert _item(client, bungalow, {ALARM_TEST: _ago(30.5)}, ALARM_TEST)["done"] is False
    assert _item(client, bungalow, {ALARM_TEST: _ago(29.5)}, ALARM_TEST)["done"] is True


def test_far_future_timestamp_is_not_done_but_small_skew_is(
    client: TestClient, bungalow: dict
):
    future = (datetime.now(timezone.utc) + timedelta(days=2000)).isoformat()
    skewed = (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat()
    assert _item(client, bungalow, {DRILL: future}, DRILL)["done"] is False
    assert _item(client, bungalow, {DRILL: skewed}, DRILL)["done"] is True


def test_naive_stamp_near_the_edge_is_read_as_utc(client: TestClient, bungalow: dict):
    """A naive stamp 29.5 days old is done only if read as UTC; any zone shift of a
    day or more would flip it, so this fails on a wrong interpretation."""
    naive = (datetime.now(timezone.utc) - timedelta(days=29.5)).replace(tzinfo=None)
    assert _item(client, bungalow, {ALARM_TEST: naive.isoformat()}, ALARM_TEST)["done"] is True


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
