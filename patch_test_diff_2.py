with open("backend/tests/test_diff.py", "r") as f:
    c = f.read()

c = c.replace('ext_room = Room(id=EXTERIOR_ID, name="Ext", type="other", source="scan", confidence=1.0, polygon=[(0, -5), (5, -5), (5, -1), (0, -1)])\n    floor = Floor(id="f1", level=0, name="Ground", height_m=3, rooms=[room, ext_room], openings=[op], objects=objects)', 'floor = Floor(id="f1", level=0, name="Ground", height_m=3, rooms=[room], openings=[op], objects=objects)')

with open("backend/tests/test_diff.py", "w") as f:
    f.write(c)
