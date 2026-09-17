"""The pymongo command logger must never emit home documents.

pymongo logs every command it issues, with the full document, at DEBUG. Since S8.4 those
documents are users' homes — floor polygons, room names, `meta.address_optional`, household
composition. Raising the root logger to DEBUG while chasing an unrelated bug would write all of
it into a hosted service's retained logs.

These tests pin the protection at the level that matters: it must hold even when someone turns
the root logger up, because "we happen to run at INFO" is a coincidence, not a safeguard.
"""

from __future__ import annotations

import logging

import app.main  # noqa: F401  — importing is what applies the configuration

PYMONGO_LOGGERS = ("pymongo", "pymongo.command")


def test_pymongo_loggers_are_pinned_to_info() -> None:
    for name in PYMONGO_LOGGERS:
        assert logging.getLogger(name).level == logging.INFO, name


def test_a_debug_root_logger_does_not_drag_pymongo_down_with_it() -> None:
    """The whole point: the pin has to survive the thing it is protecting against."""
    root = logging.getLogger()
    original = root.level
    try:
        root.setLevel(logging.DEBUG)
        for name in PYMONGO_LOGGERS:
            logger = logging.getLogger(name)
            assert not logger.isEnabledFor(logging.DEBUG), (
                f"{name} would emit whole documents — including users' home layouts — "
                "with the root logger at DEBUG"
            )
            # INFO and above still flow, so genuine operational logging is untouched.
            assert logger.isEnabledFor(logging.INFO), name
    finally:
        root.setLevel(original)


def test_application_loggers_are_not_pinned() -> None:
    """Only pymongo is held down. The app's own modules must still be debuggable, or the fix
    would have quietly cost us the ability to diagnose anything."""
    assert logging.getLogger("app.database").level == logging.NOTSET
