"""RoomPlan → HomeModel scan converter (S1.5). Pure functions only — the
FastAPI /convert endpoint (S1.6) wraps :func:`convert_scan`."""

from app.convert.converter import convert_scan
from app.convert.roomplan import RPRoom, RPStructure, RPSurface

__all__ = ["convert_scan", "RPRoom", "RPStructure", "RPSurface"]
