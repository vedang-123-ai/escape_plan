from app.models import HomeModel, Room, Floor, EXTERIOR_ID
from app.routing.graph import NavGraph, NodeKind
from app.routing.plan import Route, RouteFinding, RoutingConstraints
from app.routing.engine import _SearchResult, _edge_cost
from typing import Optional
import math

def _point_segment_distance(p: tuple[float, float], a: tuple[float, float], b: tuple[float, float]) -> float:
    ab = (b[0] - a[0], b[1] - a[1])
    ap = (p[0] - a[0], p[1] - a[1])
    denom = ab[0] ** 2 + ab[1] ** 2
    if denom < 1e-12:
        return math.dist(p, a)
    t = max(0.0, min(1.0, (ap[0] * ab[0] + ap[1] * ab[1]) / denom))
    return math.dist(p, (a[0] + t * ab[0], a[1] + t * ab[1]))

def _is_collinear(p1: tuple[float, float], p2: tuple[float, float], q1: tuple[float, float], q2: tuple[float, float], tol: float = 1e-3) -> bool:
    cross1 = (p2[0] - p1[0]) * (q1[1] - p1[1]) - (p2[1] - p1[1]) * (q1[0] - p1[0])
    cross2 = (p2[0] - p1[0]) * (q2[1] - p1[1]) - (p2[1] - p1[1]) * (q2[0] - p1[0])
    return abs(cross1) < tol and abs(cross2) < tol

def _unshared_length(p1: tuple[float, float], p2: tuple[float, float], other_segments: list[tuple[tuple[float, float], tuple[float, float]]], tol: float = 1e-3) -> float:
    dx = p2[0] - p1[0]
    dy = p2[1] - p1[1]
    length = math.hypot(dx, dy)
    if length < 1e-6:
        return 0.0
        
    intervals = []
    for (q1, q2) in other_segments:
        if not _is_collinear(p1, p2, q1, q2, tol):
            continue
        if abs(dx) > abs(dy):
            t1 = (q1[0] - p1[0]) / dx
            t2 = (q2[0] - p1[0]) / dx
        else:
            t1 = (q1[1] - p1[1]) / dy
            t2 = (q2[1] - p1[1]) / dy
            
        t_start = max(0.0, min(t1, t2))
        t_end = min(1.0, max(t1, t2))
        if t_start < t_end:
            intervals.append((t_start, t_end))
            
    intervals.sort()
    covered = 0.0
    current_end = 0.0
    for start, end in intervals:
        if start > current_end:
            current_end = start
        if end > current_end:
            covered += (end - current_end)
            current_end = end
            
    return max(0.0, (1.0 - covered) * length)

def count_exterior_walls(room: Room, floor: Floor) -> int:
    """ENGINEERING CONSTANT: exterior adjacency count.
    
    A room edge counts as exterior if it is not shared with any other room
    (> 15cm exposed), or if it carries an opening to the EXTERIOR.
    """
    exterior_edges = set()
    
    for op in floor.openings:
        if room.id in op.room_ids and EXTERIOR_ID in op.room_ids:
            if op.wall_segment.room_id == room.id:
                exterior_edges.add(op.wall_segment.edge_index)
            else:
                exterior_edges.add(f"op_{op.id}")
                
    other_segments = []
    for r in floor.rooms:
        if r.id == room.id:
            continue
        n_r = len(r.polygon)
        for i in range(n_r):
            other_segments.append((r.polygon[i], r.polygon[(i + 1) % n_r]))
            
    n = len(room.polygon)
    for i in range(n):
        if i in exterior_edges:
            continue
        p1 = room.polygon[i]
        p2 = room.polygon[(i + 1) % n]
        
        # ENGINEERING CONSTANT: 15cm exposed length means it's an exterior wall
        if _unshared_length(p1, p2, other_segments) > 0.15:
            exterior_edges.add(i)
                
    return len(exterior_edges)

def count_exterior_openings(room: Room, floor: Floor) -> int:
    count = 0
    for op in floor.openings:
        if room.id in op.room_ids and EXTERIOR_ID in op.room_ids:
            count += 1
    return count


import heapq
from app.routing.graph import NodeKind

def dijkstra_to_all_rooms(
    graph: NavGraph,
    source: str,
    openings: dict,
    constraints: RoutingConstraints
):
    dist: dict[str, float] = {source: 0.0}
    prev: dict[str, tuple[str, any]] = {}
    heap: list[tuple[float, str]] = [(0.0, source)]
    done: set[str] = set()

    while heap:
        d, node = heapq.heappop(heap)
        if node in done:
            continue
        done.add(node)
        for edge in graph.neighbors(node):
            cost = _edge_cost(edge, node, graph, openings, constraints)
            if cost is None:
                continue
            neighbor = edge.other(node)
            if neighbor == EXTERIOR_ID:
                continue
                
            nd = d + cost
            if nd < dist.get(neighbor, float("inf")):
                dist[neighbor] = nd
                prev[neighbor] = (node, edge)
                heapq.heappush(heap, (nd, neighbor))

    results = {}
    for node_id, d in dist.items():
        if graph.nodes[node_id].kind == NodeKind.room:
            path = []
            edges = []
            curr = node_id
            while curr != source:
                p, e = prev[curr]
                path.append(curr)
                edges.append(e)
                curr = p
            path.append(source)
            path.reverse()
            edges.reverse()
            results[node_id] = _SearchResult(path=path, edges=edges, cost=d)
            
    return results

def find_tornado_shelter(
    home: HomeModel,
    graph: NavGraph,
    source_room_id: str,
    openings: dict,
    constraints: RoutingConstraints
) -> tuple[Optional[str], Optional[Route]]:
    """Find the best tornado safe room from the source room."""
    reachable = dijkstra_to_all_rooms(graph, source_room_id, openings, constraints)
    
    floors = {f.id: f for f in home.floors}
    rooms = {r.id: r for f in home.floors for r in f.rooms}
    
    candidates = []
    for target_id, search_result in reachable.items():
        room = rooms[target_id]
        floor = floors[graph.nodes[target_id].floor_id]
        
        ext_walls = count_exterior_walls(room, floor)
        ext_openings = count_exterior_openings(room, floor)
        dist = sum(e.weight for e in search_result.edges)
        
        if floor.level > 0:
            continue
            
        candidates.append({
            "room_id": target_id,
            "level": floor.level,
            "ext_walls": ext_walls,
            "ext_openings": ext_openings,
            "dist": dist,
            "search_result": search_result
        })
        
    if not candidates:
        return None, None
        
    # Mobile home check: if it's a single-story home and EVERY room touches an exterior wall,
    # it is indistinguishable from a mobile home or lacks any safe core.
    if len(home.floors) == 1 and all(c["ext_walls"] > 0 for c in candidates):
        return None, None
    best = min(candidates, key=lambda c: (
        c["level"],
        c["ext_walls"],
        c["ext_openings"],
        c["dist"]
    ))
    
    route = _route_from_tornado_search(best["search_result"], graph, home)
    return best["room_id"], route

def _route_from_tornado_search(
    result: _SearchResult, graph: NavGraph, home: HomeModel
) -> Route:
    from app.routing.plan import Waypoint, Route
    from app.routing.graph import NodeKind, EdgeKind
    
    stairs_by_id = {s.id: s for s in home.stairs}
    waypoints: list[Waypoint] = []
    uses_stairs = False

    for i, node_id in enumerate(result.path):
        node = graph.nodes[node_id]
        if i > 0:
            edge = result.edges[i - 1]
            if edge.kind == EdgeKind.room_opening and edge.path is not None:
                interior = list(edge.path[1:-1])
                if result.path[i - 1] != edge.a:
                    interior.reverse()
                opening_id = edge.b
                for px, py in interior:
                    waypoints.append(
                        Waypoint(
                            x=px, y=py,
                            floor_id=graph.nodes[opening_id].floor_id,
                            node_id=opening_id,
                            kind="path",
                        )
                    )
            if edge.kind == EdgeKind.stair:
                uses_stairs = True
                s = stairs_by_id[edge.via]
                cx = sum(p[0] for p in s.footprint) / len(s.footprint)
                cy = sum(p[1] for p in s.footprint) / len(s.footprint)
                waypoints.append(
                    Waypoint(
                        x=cx,
                        y=cy,
                        floor_id=s.from_.floor_id,
                        node_id=s.id,
                        kind="stair",
                    )
                )

        waypoints.append(
            Waypoint(
                x=node.position[0] if node.position else 0.0,
                y=node.position[1] if node.position else 0.0,
                floor_id=node.floor_id or "unknown",
                node_id=node_id,
                kind="room" if node.kind == NodeKind.room else "opening",
            )
        )

    # For tornado, the exit_id is the shelter room itself.
    exit_id = result.path[-1]
    length_m = sum(e.weight for e in result.edges)
    return Route(
        waypoints=waypoints,
        length_m=round(length_m, 3),
        uses_stairs=uses_stairs,
        uses_window=False, # tornado route never uses windows
        exit_id=exit_id,
    )
