import Fluent

struct ReferenceAddEmbedMapURLs: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("references")
			.field("embed_map", .string)
			.update()

		let references = try await Reference.query(on: database).all()
		try await database.transaction { db in
			for reference in references {
				if reference.embedMap == nil {
					reference.embedMap = reference.website.replacingOccurrences(of: ".de/l", with: ".de/embed/l")
					try await reference.save(on: db)
				}
			}
		}
	}

	func revert(on database: Database) async throws {
		try await database.schema("references")
			.deleteField("embed_map")
			.update()
	}
}
