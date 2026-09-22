---
id: severe-weather-tornado
org: NOAA / NWS / FEMA / Red Cross
doc_title: Tornado Safety — Choosing a Shelter Location
url: https://www.weather.gov/safety/tornado-during
retrieved: 2026-09-21
topics: [tornado, severe-weather, shelter, during-tornado]
additional_source_ids: [noaa-tornado, noaa-tornado-ww, noaa-tornado-shelter, fema-tornado-ready, redcross-tornado]
---

# Tornado Safety — Choosing a Shelter Location

Where to go when a warning is issued. Purpose-built safe rooms are `tornado-safe-rooms.md`; alerts and
manufactured homes are `tornado-warnings-and-mobile-homes.md`.

## The shelter hierarchy

Four agencies describe the same ranking, best first:

1. **A safe room or storm shelter.** Ready.gov puts first "a safe room built using FEMA criteria or a
   storm shelter built to ICC 500 standards" [cite: fema-tornado-ready]. The Red Cross likewise says to
   find a safe room built to withstand high winds [cite: redcross-tornado]. See `tornado-safe-rooms.md`.
2. **A basement.** NWS: if you are in a tornado warning at your house, go to your basement, safe room, or
   an interior room away from windows [cite: noaa-tornado].
3. **A small interior windowless room on the lowest floor.** Ready.gov calls this "the next best
   protection… a small, interior, windowless room or basement on the lowest level of a sturdy building"
   [cite: fema-tornado-ready]. The NWS warning definition says to move to an interior room on the lowest
   floor of a sturdy building and avoid windows [cite: noaa-tornado-ww]. The Red Cross describes the same
   fallback: a small room with no windows on the lowest level of a sturdy building
   [cite: redcross-tornado]. In practice this is a closet, bathroom, or interior hallway without windows
   [cite: noaa-tornado-shelter].

## The rule that drives the app's objective function (editorial note, not safety guidance)

**Put as many walls between yourself and the outside as possible** [cite: noaa-tornado-shelter].

This single sentence is what makes tornado shelter selection computable from a floor plan: lowest floor,
most interior room, fewest exterior walls, no windows. Each term is sourced above.

Stay away from windows [cite: noaa-tornado] [cite: noaa-tornado-ww]. Avoid large open rooms such as
cafeterias, gymnasiums, and auditoriums — the NWS names these for workplaces and schools, and the
underlying reason, long roof spans with no interior walls, applies to any large open space
[cite: noaa-tornado].

## Protecting your body once you are there

- **Get under something sturdy,** such as a heavy table, or use a mattress to protect yourself from flying
  debris [cite: noaa-tornado-shelter].
- **Protect your head.** Most injuries associated with high winds are from flying debris, so remember to
  protect your head; if available, put on a bicycle or motorcycle helmet to protect yourself from head
  injuries [cite: noaa-tornado-shelter].
- **Bring pets** if time allows [cite: noaa-tornado].

## If you are not at home

- **Outside:** seek shelter inside a sturdy building immediately. Sheds and storage facilities are not
  safe, and neither is a mobile home or tent [cite: noaa-tornado]. If no sturdy shelter is available, get
  to a low spot and cover your head from flying debris [cite: noaa-tornado-shelter].
- **In a vehicle:** being in a vehicle during a tornado is not safe. The best course of action is to drive
  to the closest shelter. If you cannot reach one, either get down in your car and cover your head, or
  abandon the car and seek shelter in a low-lying area such as a ditch or ravine [cite: noaa-tornado].
- **Do not shelter under a highway overpass.** It does not provide adequate shelter during a tornado and
  can cause increased wind speeds due to a tunneling effect [cite: noaa-tornado-shelter].

## Implications for the app (editorial note, not safety guidance)

The safe-location rule — lowest floor, most interior room, as many walls as possible between you and the
outside — is the exact inverse of fire escape guidance, which prioritises moving to the exterior. This
inversion is what the engine's per-peril objective function encodes, and it is why one home model can
produce opposite routes for two perils.
