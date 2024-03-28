import Fluent

struct CreateQso: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("qsos")
			.id()
			.field("activator_id", .uuid, .required, .references("users", "id"))
			.field("hunter_id", .uuid, .references("users", "id"))
			.field("reference_id", .uuid, .references("references", "id"))
			.field("hunted_reference_id", .uuid, .references("references", "id"))
			.field("date", .datetime, .required)
			.field("call", .string, .required)
			.field("station_callsign", .string, .required)
			.field("freq", .int)
			.field("mode", .string)
			.field("rst_sent", .string)
			.field("rst_rcvd", .string)
			.create()
	}
	
	func revert(on database: Database) async throws {
		try await database.schema("qsos").delete()
	}
}

