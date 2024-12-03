import Fluent

struct CreateCallsign: AsyncMigration {
	func prepare(on database: Database) async throws {
		let kind = try await database.enum("callsign_kind_enum")
			.case("licensed")
			.case("unlicensed")
			.case("training")
			.create()

		try await database.schema("callsigns")
			.id()
			.field("callsign", .string, .required)
		// Unfortunately we can't really model required 1:1 relationships in FluentKit, hence the user_id field on callsign is not enforced as required.
			.field("user_id", .uuid, .references("users", "id"))
			.field("kind", kind, .required)
			.foreignKey("user_id", references: UserModel.schema, .id, onDelete: .cascade)
			.unique(on: "callsign")
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("callsigns").delete()
		try await database.enum("callsign_kind_enum").delete()

	}
}
