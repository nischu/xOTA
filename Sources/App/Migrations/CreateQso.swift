import Fluent

struct CreateQso: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("qsos")
			.id()
			.field("activator_id", .uuid, .required, .references("users", "id"))
			.field("activator_trainer_id", .uuid, .references("users", "id"))
			.field("hunter_id", .uuid, .references("users", "id"))
			.field("reference_id", .uuid, .references("references", "id"))
			.field("hunted_reference_id", .uuid, .references("references", "id"))
			.field("date", .datetime, .required)
			.field("call", .string, .required)
			.field("station_callsign", .string, .required)
			.field("operator", .string)
			.field("contacted_operator", .string)
			.field("contacted_operator_user_id", .uuid, .references("users", "id"))
			.field("freq", .int)
			.field("mode", .string)
			.field("rst_sent", .string)
			.field("rst_rcvd", .string)
			.field("modification_date", .datetime)
			.create()
	}
	
	func revert(on database: Database) async throws {
		try await database.schema("qsos").delete()
	}
}

