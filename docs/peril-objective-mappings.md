# Peril Objective Mappings

This document defines the routing objective for each peril type supported by the engine (`fire`, `tornado`, `earthquake`), the corpus justification for those objectives, and any engineering constants introduced to resolve ambiguity.

## Fire (Default)

**Objective**: Find the shortest path to a viable exterior exit (doors strongly preferred over windows).
**Corpus Justification**: "Get out as quickly and safely as possible" ([cite: redcross-escape-plan]).
**Implementation**: Dijkstra's algorithm from the room node to `EXTERIOR_ID`.
**Engineering Constants**: 
- `WINDOW_EXIT_PENALTY` (12.0m) to enforce the preference for doors unless a door route is absurdly long or blocked.

## Tornado (Severe Weather)

**Objective**: Find the safest reachable room for sheltering in place.
**Corpus Justification**: The safest location is the lowest floor, most interior room, with as many walls between you and the outside as possible ([cite: noaa-tornado]). Mobile homes are never safe, and occupants must seek shelter elsewhere ([cite: noaa-tornado], [cite: redcross-tornado]).
**Implementation**: Dijkstra's algorithm to compute shortest paths to all reachable rooms. The best room is selected by priority:
  1. Lowest floor available (`floor.level`)
  2. Fewest exterior-wall adjacencies (an interior room with zero exterior walls wins)
  3. Fewest openings to the exterior
  4. Shortest path distance (tie-breaker)
**Engineering Constants**:
- **Exterior Adjacency Tolerance** (0.15m): A room edge is considered adjacent to the exterior if its midpoint lies within 15 cm of a footprint boundary edge.
- **Mobile Home Check**: If every reachable room touches an exterior wall, a `no_viable_safe_room` finding is returned.

## Earthquake

**Objective**: Find the nearest sturdy object to get under within the room, and provide post-shaking evacuation routes.
**Corpus Justification**: "Drop, Cover, and Hold On" under a sturdy desk or table ([cite: shakeout-guidance]). Post-shaking evacuation is necessary if instructed by authorities, using regular escape paths ([cite: fema-earthquake]).
**Implementation**: 
- **Cover points**: Returns the first qualifying object (`category == "table"`) in the room. If none is found, it returns an honest `no_cover_in_room` finding advising to drop to the ground.
- **Post-shaking evacuation**: Identical to Fire evacuation (uses the same `_dijkstra_to_exterior` logic).
**Engineering Constants**: None introduced. Object qualification is strictly limited to the `table` category as permitted by the schema.
