with open("escape_plan/Networking/APIClient+Convert.swift", "r") as f:
    c = f.read()

c = c.replace("    let diff_objects: [FloorObject]\n    }", "    let diff_objects: [FloorObject]\n    let obstructions: [Obstruction]\n}")

obstruction_struct = """
struct Obstruction: Codable, Equatable {
    var kind: String
    var room_id: String
    var room_name: String
    var floor_id: String
    var opening_id: String
    var object_ids: [String]
    var object_categories: [String]
    var passable_width_m: Double
    var required_width_m: Double
    var target_width_m: Double
    var suggested_move_m: Double
}
"""

c = c.replace("struct DiffRequest", obstruction_struct + "\nstruct DiffRequest")

with open("escape_plan/Networking/APIClient+Convert.swift", "w") as f:
    f.write(c)
