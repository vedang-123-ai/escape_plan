---
id: tornado-warnings-and-mobile-homes
org: NOAA / NWS / FEMA / Red Cross
doc_title: Tornado Safety — Warnings, Alerts, and Homes That Are Not Shelters
url: https://www.weather.gov/safety/tornado-ww
retrieved: 2026-09-21
topics: [tornado, alerts, watch-warning, mobile-homes, accessibility]
additional_source_ids: [noaa-tornado-ww, noaa-tornado, noaa-nwr-accessibility, fema-tornado-ready, redcross-tornado]
---

# Tornado Safety — Warnings, Alerts, and Homes That Are Not Shelters

Knowing which alert has been issued determines whether you prepare or move, and some homes have no safe
location at all. Both facts change what a household plan should say.

## Watch, Warning, Emergency

The National Weather Service issues three key alerts [cite: noaa-tornado-ww]:

- **Tornado Watch — Be Prepared.** Tornadoes are possible in and near the watch area. Review and discuss
  your emergency plans, take inventory of your supplies, and check your safe room. Be ready to act quickly
  if a warning is issued. Watches are issued by the Storm Prediction Center and typically cover a large
  area — numerous counties or even states [cite: noaa-tornado-ww].
- **Tornado Warning — Take Action.** A tornado has been sighted or indicated by weather radar. There is
  imminent danger to life and property. Move to an interior room on the lowest floor of a sturdy building
  and avoid windows. If in a mobile home, a vehicle, or outdoors, move to the closest substantial shelter
  and protect yourself from flying debris. Warnings are issued by the local forecast office and cover a
  much smaller area, around the size of a city or small county [cite: noaa-tornado-ww].
- **Tornado Emergency — Seek Shelter Immediately.** The NWS's highest alert level, issued when a violent
  tornado has touched down and catastrophic damage is confirmed. Immediately seek refuge in the safest
  location possible [cite: noaa-tornado-ww].

The practical difference: a **watch** is when you check that your plan still works; a **warning** is when
you execute it [cite: noaa-tornado-ww].

## Getting the alert at all

- Sign up for your community's warning system. The Emergency Alert System (EAS) and NOAA Weather Radio
  also provide emergency alerts. If your community has sirens, become familiar with the warning tone
  [cite: fema-tornado-ready].
- Pay attention to EAS, NOAA Weather Radio, or local alerting systems for current information and
  instructions [cite: fema-tornado-ready].
- Sign up for free emergency alerts from your local government, plan to monitor local weather and news,
  keep a way to charge a phone, and keep a battery-powered radio for a power outage
  [cite: redcross-tornado].
- **You may not always receive a tornado warning.** Know the signs of a tornado and take shelter if you
  suspect one [cite: redcross-tornado].

## If you are deaf or hard of hearing

Outdoor sirens are audible warnings and are not an accessible alert channel indoors. NOAA Weather Radio
(NWR) offers non-verbal information embedded in its broadcasts to provide timely, critical warnings of
life-threatening events to the deaf and hard of hearing [cite: noaa-nwr-accessibility]. Some receivers have
special output connectors that activate alerting devices such as **vibrators, bed shakers, pillow
vibrators, strobe lights** and other alerting systems [cite: noaa-nwr-accessibility].

With **Specific Area Message Encoding (SAME)** technology, NWR receivers can be programmed to alarm for
specific events — tornado, flash flood — and for specific counties [cite: noaa-nwr-accessibility]. When a
warning is received, a SAME receiver turns itself on, sounds an alarm, activates a warning light, writes a
short message on the display, and activates connected external devices such as strobe lights, sirens and
vibrators [cite: noaa-nwr-accessibility].

An NWR receiver can also be connected to an existing home security system, much as a doorbell or smoke
detector would be [cite: noaa-nwr-accessibility]. The NWS notes it does not guarantee the operation of any
listed equipment and does not endorse any product [cite: noaa-nwr-accessibility] — so this app names the
capability, never a brand.

## Homes with no safe location

**Mobile, manufactured and trailer homes and recreational vehicles are not safe in high wind events**
[cite: redcross-tornado]. The NWS states the same: a mobile home is not safe shelter, along with sheds and
storage facilities [cite: noaa-tornado]. Under a warning, someone in a mobile home should move to the
closest substantial shelter [cite: noaa-tornado-ww].

Because there is no interior room that makes such a home safe, the plan has to be made **in advance**: plan
ahead by finding a sturdy building to shelter in before a tornado watch or warning is ever issued
[cite: redcross-tornado].

**Design intent (editorial note, not safety guidance, and not a description of current behaviour).** The
honest output for a manufactured home is that it has no adequate shelter and the plan is a pre-identified
destination elsewhere, rather than a ranked interior room. **The engine does not do this today, by
deliberate choice:** construction type is not derivable from a floor-plan footprint and `HomeModel` has no
field for it, so an earlier mobile-home check was removed after it misfired on 4 of 5 fixtures (see
`backend/app/routing/perils/tornado.py`). What ships instead is a conditional finding when no interior
room is reachable. Nothing in this app should tell a resident it has identified their home as a
manufactured home.

## Practising

Practise moving quickly to the safe locations you identified, with the entire household
[cite: redcross-tornado]. Create a personal support team of people you may assist and who can assist you
[cite: redcross-tornado]. If you live in a mobile home, practise going to your safe place
[cite: redcross-tornado].

## After

Be aware of carbon monoxide poisoning: do not use gasoline, propane, natural gas or charcoal-burning
devices inside a home, basement, garage, tent or camper, or outside near an open window. Carbon monoxide
cannot be seen or smelled but can kill quickly; if you start to feel sick, dizzy or weak, get to fresh air
right away [cite: redcross-tornado].
