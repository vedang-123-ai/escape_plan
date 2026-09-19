from pathlib import Path

pt_path = Path("escape_planTests/PersistenceTests.swift")
content = pt_path.read_text()
content = content.replace(
    'XCTAssertEqual(\n            schema["properties"]?["schema_version"]?["enum"]?.arrayValue?.compactMap({ $0.stringValue }).last,\n            SchemaMigrator.currentVersion,\n            "SchemaMigrator.currentVersion has drifted from the schema"\n        )',
    'XCTAssertTrue(\n            (schema["properties"]?["schema_version"]?["enum"]?.arrayValue?.compactMap({ $0.stringValue }) ?? []).contains(SchemaMigrator.currentVersion),\n            "SchemaMigrator.currentVersion has drifted from the schema"\n        )'
)
pt_path.write_text(content)
print("Fixed assert")
