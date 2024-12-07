import Fluent

struct CreateAward: AsyncMigration {
	func prepare(on database: Database) async throws {
		let state = try await database.enum("award_state_enum")
			.case("waiting-to-render")
			.case("rendering")
			.case("issued")
			.create()

		try await database.schema("awards")
			.id()
			.field("user_id", .uuid, .required, .references("users", "id"))
			.field("name", .string, .required)
			.field("kind", .string, .required)
			.field("state", state, .required)
			.field("date_issued", .datetime, .required)
			.field("filename", .string)
			.foreignKey("user_id", references: UserModel.schema, .id, onDelete: .cascade)
			.unique(on: "id")
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("awards").delete()
		try await database.enum("award_state_enum").delete()
	}
}
