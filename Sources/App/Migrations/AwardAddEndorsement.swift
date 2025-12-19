import Fluent

struct AwardAddEndorsement: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("awards")
			.field("endorsement", .string)
			.update()
	}

	func revert(on database: Database) async throws {
		try await database.schema("awards")
			.deleteField("endorsement")
			.update()
	}
}
