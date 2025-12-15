import Fluent

struct CreateReference: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("references")
			.id()
			.field("title", .string, .required)
			.field("website", .string, .required)
			.field("embed_map", .string)
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("references").delete()
	}
}

