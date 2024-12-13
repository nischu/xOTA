import Fluent

struct CreateUserRole: AsyncMigration {
	func prepare(on database: Database) async throws {
		let specialRoles = try await database.enum("user_role_enum")
			.case("admin")
			.create()

		try await database.schema("user_roles")
			.id()
			.field("user_id", .uuid, .required, .references("users", "id"))
			.foreignKey("user_id", references: UserModel.schema, .id, onDelete: .cascade)
			.field("role", specialRoles, .required)
			.create()
	}
	
	func revert(on database: Database) async throws {
		try await database.schema("user_roles").delete()
		try await database.enum("user_role_enum").delete()
	}
}
