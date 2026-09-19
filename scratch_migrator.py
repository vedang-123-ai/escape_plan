from pathlib import Path

sm_path = Path("escape_plan/Persistence/SchemaMigrator.swift")
content = sm_path.read_text()

content = content.replace(
    'static let currentVersion = "1.1"',
    'static let currentVersion = "2.0"'
)

new_migration = """
        "1.1": { document in
            guard case .object(var root) = document.body else {
                throw PersistenceError.missingSchemaVersion
            }
            root["schema_version"] = .string("2.0")
            return HomeDocument(body: .object(root))
        },
"""

content = content.replace(
    'static let migrations: [String: (HomeDocument) throws -> HomeDocument] = [',
    'static let migrations: [String: (HomeDocument) throws -> HomeDocument] = [\n' + new_migration
)

sm_path.write_text(content)
print("Added 1.1->2.0 migration")
