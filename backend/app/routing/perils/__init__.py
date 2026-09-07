"""Multi-peril objective routing: earthquake cover and tornado safe-room searches."""

from .earthquake import find_cover_object
from .tornado import count_exterior_walls, count_exterior_openings, dijkstra_to_all_rooms, find_tornado_shelter
