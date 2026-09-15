with open("backend/app/routing/object_hazards.py", "r") as f:
    c = f.read()

c = c.replace("    door_approach_radius_m: EngineeringConstant", "    door_approach_radius_m: EngineeringConstant\n    registration_tolerance_m: EngineeringConstant")

with open("backend/app/routing/object_hazards.py", "w") as f:
    f.write(c)

