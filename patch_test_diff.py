with open("backend/tests/test_diff.py", "r") as f:
    c = f.read()

c = c.replace('from app.models import HomeModel, FloorObject, Room, Floor, Opening, WallSegmentRef', 'from app.models import HomeModel, FloorObject, Room, Floor, Opening, WallSegmentRef, EXTERIOR_ID')
c = c.replace('room_ids=["r1", "exterior"]', 'room_ids=["r1", EXTERIOR_ID]')
c = c.replace('id="exterior"', 'id=EXTERIOR_ID')

with open("backend/tests/test_diff.py", "w") as f:
    f.write(c)
