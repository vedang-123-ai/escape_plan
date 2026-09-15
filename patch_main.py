with open("backend/app/main.py", "r") as f:
    lines = f.readlines()

new_lines = []
skip = False
for line in lines:
    if line.startswith("class DiffRequest(BaseModel):"):
        skip = True
    elif skip and line.startswith("from app.ai.agent import AgentError"):
        skip = False
        new_lines.append(line)
    elif not skip:
        new_lines.append(line)

c = "".join(new_lines)
c = c.replace("from app.config import get_settings, get_thresholds", "from app.config import get_settings, get_thresholds, get_object_hazard_thresholds")
c = c.replace("from app.routing.diff import compute_diff", "from app.routing.diff import compute_diff, DiffRequest, DiffResult")

# Replace diff_obstructions implementation
diff_start = c.find("def diff_obstructions(")
diff_str = """def diff_obstructions(
    req: DiffRequest,
    thresholds: EgressThresholds = Depends(get_thresholds)
) -> DiffResult:
    tol = get_object_hazard_thresholds().engineering_constants.registration_tolerance_m.value
    return compute_diff(req.stored_model, req.scan_model, req.target_room_id, thresholds, tol)
"""
c = c[:diff_start] + diff_str

with open("backend/app/main.py", "w") as f:
    f.write(c)
