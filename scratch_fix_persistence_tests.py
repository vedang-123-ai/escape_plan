from pathlib import Path

pt_path = Path("escape_planTests/PersistenceTests.swift")
content = pt_path.read_text()

content = content.replace(
    '.setting("schema_version", to: .string("2.0"))',
    '.setting("schema_version", to: .string("3.0"))'
)

content = content.replace(
    '.documentTooNew(documentVersion: "2.0", supportedVersion: "1.1")',
    '.documentTooNew(documentVersion: "3.0", supportedVersion: "2.0")'
)

content = content.replace(
    '.migrationUnavailable(fromVersion: "0.9", toVersion: "1.1")',
    '.migrationUnavailable(fromVersion: "0.9", toVersion: "2.0")'
)

pt_path.write_text(content)
print("Fixed PersistenceTests.swift")
