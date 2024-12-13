import Fluent

struct CreateUserCredential: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("user_credentials")
			.id()
			.field("user_id", .uuid, .required, .references("users", "id"))
			.foreignKey("user_id", references: UserModel.schema, .id, onDelete: .cascade)
			.field("auth_provider", .string, .required)
			.field("login_identifier", .string, .required)
			.field("additional_storage", .string)
			.unique(on: "auth_provider", "login_identifier")
			.unique(on: "auth_provider", "user_id")
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("user_credentials").delete()
	}
}
