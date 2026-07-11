"""Routing engine CLI (S1.2 acceptance):

    cd backend
    python3 -m app.routing plan ../schema/fixtures/twostory.json --pretty
    python3 -m app.routing plan ../schema/fixtures/twostory.json --avoid-stairs --pretty

I/O lives here; the engine modules stay pure.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from app.models import HomeModel
from app.routing.egress import EgressThresholds
from app.routing.engine import compute_route_plan
from app.routing.plan import RoutingConstraints

THRESHOLDS_PATH = (
    Path(__file__).resolve().parents[2] / "corpus" / "egress_thresholds.json"
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python3 -m app.routing")
    sub = parser.add_subparsers(dest="command", required=True)
    plan_cmd = sub.add_parser("plan", help="Compute a RoutePlan for a HomeModel JSON file")
    plan_cmd.add_argument("file", type=Path, help="HomeModel JSON file")
    plan_cmd.add_argument("--pretty", action="store_true", help="Indent the JSON output")
    plan_cmd.add_argument("--avoid-stairs", action="store_true")
    plan_cmd.add_argument("--avoid-windows", action="store_true")
    plan_cmd.add_argument("--max-sill", type=float, default=None, metavar="METERS")
    args = parser.parse_args(argv)

    home = HomeModel.model_validate(json.loads(args.file.read_text()))
    thresholds = EgressThresholds.from_corpus(
        json.loads(THRESHOLDS_PATH.read_text())
    )
    constraints = RoutingConstraints(
        avoid_stairs=args.avoid_stairs,
        avoid_windows=args.avoid_windows,
        max_sill_height_m=args.max_sill,
    )
    route_plan = compute_route_plan(home, thresholds, constraints)
    print(
        route_plan.model_dump_json(indent=2 if args.pretty else None)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
