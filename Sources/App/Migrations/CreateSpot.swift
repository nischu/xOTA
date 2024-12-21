import Fluent

struct CreateSpot: AsyncMigration {
	func prepare(on database: Database) async throws {

		let state = try await database.enum("spot_state")
			.case("active")
			.case("qrt")
			.create()

		try await database.schema("spots")
			.id()
			.field("activator_id", .uuid, .required, .references("users", "id"))
			.foreignKey("activator_id", references: UserModel.schema, .id, onDelete: .cascade)
			.field("activator_trainer_id", .uuid, .references("users", "id"))
			.foreignKey("activator_trainer_id", references: UserModel.schema, .id, onDelete: .setNull)
			.field("reference_id", .uuid, .references("references", "id"))
			.field("station_callsign", .string, .required)
			.field("operator", .string)
			.field("freq", .int, .required)
			.field("mode", .string, .required)
			.field("state", state, .required)
			.field("modification_date", .datetime)
			.create()
	}
	
	func revert(on database: Database) async throws {
		try await database.schema("spots").delete()
		try await database.enum("spot_state").delete()
	}
}

