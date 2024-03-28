import Fluent

struct CreateUser: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("users")
			.id()
			.field("callsign", .string, .required)
			.field("ccchub-user", .string)
			.field("hashed-password", .string)
			.unique(on: "callsign", "ccchub-user")
			.create()
	}
	
	func revert(on database: Database) async throws {
		try await database.schema("users").delete()
	}
}
