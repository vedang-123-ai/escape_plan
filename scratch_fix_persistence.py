from pathlib import Path

pt_path = Path("escape_planTests/PersistenceTests.swift")
content = pt_path.read_text()
content = content.replace(
    'schema["properties"]?["schema_version"]?["const"]?.stringValue',
    'schema["properties"]?["schema_version"]?["enum"]?.arrayValue?.compactMap({ $0.stringValue }).last'
)
pt_path.write_text(content)
print("Fixed testCurrentVersionMatchesTheSchemaContract")
