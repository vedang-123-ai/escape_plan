with open("backend/app/routing/diff.py", "r") as f:
    c = f.read()

c = c.replace("if op.room_ids == [EXTERIOR_ID]:", "if EXTERIOR_ID in op.room_ids:")

with open("backend/app/routing/diff.py", "w") as f:
    f.write(c)

