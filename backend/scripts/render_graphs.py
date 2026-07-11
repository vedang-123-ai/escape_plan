"""Dev tool: render each fixture's navigation graph over its floor plan (S1.1 handoff).

Usage, from the repo root:

    python3 backend/scripts/render_graphs.py

Writes docs/graphs/<fixture>.png. Matplotlib is a dev-only dependency; the
routing modules themselves stay pure and dependency-light.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "backend"))

from app.models import EXTERIOR_ID, HomeModel  # noqa: E402
from app.routing.egress import EgressThresholds  # noqa: E402
from app.routing.graph import EdgeKind, NodeKind, build_graph  # noqa: E402

FIXTURES = ["bungalow", "apartment", "twostory"]
OUT_DIR = REPO_ROOT / "docs" / "graphs"

FLOOR_OFFSET_X = 14.0  # draw each floor side by side


def main() -> None:
    thresholds = EgressThresholds.from_corpus(
        json.loads((REPO_ROOT / "backend" / "corpus" / "egress_thresholds.json").read_text())
    )
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for name in FIXTURES:
        home = HomeModel.model_validate(
            json.loads((REPO_ROOT / "schema" / "fixtures" / f"{name}.json").read_text())
        )
        graph = build_graph(home, thresholds)
        floor_dx = {f.id: i * FLOOR_OFFSET_X for i, f in enumerate(home.floors)}

        fig, ax = plt.subplots(figsize=(11, 6))
        for floor in home.floors:
            dx = floor_dx[floor.id]
            for room in floor.rooms:
                xs = [p[0] + dx for p in room.polygon] + [room.polygon[0][0] + dx]
                ys = [p[1] for p in room.polygon] + [room.polygon[0][1]]
                ax.plot(xs, ys, color="#999999", linewidth=1)
                ax.annotate(
                    room.name,
                    (sum(p[0] + dx for p in room.polygon) / len(room.polygon),
                     max(p[1] for p in room.polygon) - 0.35),
                    fontsize=7, color="#666666", ha="center",
                )
            ax.annotate(
                floor.name, (dx + 0.2, -1.2), fontsize=9, color="#333333"
            )

        def pos(node_id: str):
            node = graph.nodes[node_id]
            if node.kind == NodeKind.exterior:
                return None
            x, y = node.position
            return (x + floor_dx[node.floor_id], y)

        drawn = set()
        for node_id, edges in graph.adjacency.items():
            for e in edges:
                key = (min(e.a, e.b), max(e.a, e.b), e.via)
                if key in drawn:
                    continue
                drawn.add(key)
                pa, pb = pos(e.a), pos(e.b)
                if pa is None or pb is None:  # exit crossing → short stub outward
                    p = pa or pb
                    ax.plot([p[0], p[0]], [p[1], p[1] - 0.8], color="#2e7d32",
                            linewidth=2)
                    continue
                style = dict(color="#1565c0", linewidth=1)
                if e.kind == EdgeKind.stair:
                    style = dict(color="#e65100", linewidth=2, linestyle="--")
                ax.plot([pa[0], pb[0]], [pa[1], pb[1]], **style)

        for node_id, node in graph.nodes.items():
            p = pos(node_id)
            if p is None:
                continue
            if node.kind == NodeKind.room:
                ax.plot(*p, "o", color="#1565c0", markersize=6)
            elif node_id in graph.exits:
                ax.plot(*p, "s", color="#2e7d32", markersize=6)
            elif node_id in graph.excluded_exits:
                ax.plot(*p, "x", color="#c62828", markersize=8)
            else:
                ax.plot(*p, "s", color="#8e24aa", markersize=4)

        ax.set_title(
            f"{home.name} — navigation graph "
            "(green ■ viable exit, red ✕ excluded window, orange ─ ─ stairs)"
        )
        ax.set_aspect("equal")
        ax.axis("off")
        out = OUT_DIR / f"{name}.png"
        fig.savefig(out, dpi=160, bbox_inches="tight")
        plt.close(fig)
        print(f"wrote {out}")


if __name__ == "__main__":
    main()
