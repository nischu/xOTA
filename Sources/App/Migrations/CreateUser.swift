import Fluent

struct CreateUser: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("users")
			.id()
			.field("primary-callsign", .uuid, .references("callsigns", "id"))
			.unique(on: "primary-callsign")
			.create()
	}
	
	func revert(on database: Database) async throws {
		try await database.schema("users").delete()
	}
}
