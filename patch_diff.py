import re

with open("backend/app/routing/diff.py", "r") as f:
    c = f.read()

# Replace if op.room_ids == ["exterior"]: with if op.room_ids == [EXTERIOR_ID]:
c = c.replace('if op.room_ids == ["exterior"]:', 'if op.room_ids == [EXTERIOR_ID]:')
# Add import EXTERIOR_ID at top
c = c.replace('from app.models import HomeModel, FloorObject, Room', 'from app.models import HomeModel, FloorObject, Room, EXTERIOR_ID')

with open("backend/app/routing/diff.py", "w") as f:
    f.write(c)
