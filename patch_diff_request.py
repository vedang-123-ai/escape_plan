import re
with open("backend/app/routing/diff.py", "r") as f:
    c = f.read()

diff_req = """class DiffRequest(BaseModel):
    stored_model: HomeModel
    scan_model: HomeModel
    target_room_id: str

"""

c = c.replace("class DiffResult(BaseModel):", diff_req + "class DiffResult(BaseModel):")
with open("backend/app/routing/diff.py", "w") as f:
    f.write(c)

