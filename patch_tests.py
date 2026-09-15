with open("backend/tests/test_diff.py", "r") as f:
    c = f.read()

c = c.replace('room_ids=["r1", EXTERIOR_ID]', 'room_ids=["r1", "r2"]')

with open("backend/tests/test_diff.py", "w") as f:
    f.write(c)

with open("backend/tests/test_object_hazards.py", "r") as f:
    c = f.read()

import re
c = re.sub(r'door_approach_radius_m=EngineeringConstant\(value=0\.6\)\n\s*\)', 'door_approach_radius_m=EngineeringConstant(value=0.6),\n                registration_tolerance_m=EngineeringConstant(value=0.3)\n            )', c)

with open("backend/tests/test_object_hazards.py", "w") as f:
    f.write(c)
