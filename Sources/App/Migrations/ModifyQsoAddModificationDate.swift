import Fluent
import Foundation

struct ModifyQsoAddModificationDate: AsyncMigration {
	func prepare(on database: Database) async throws {
		do {
			try await database.schema("qsos")
				.field("modification_date", .datetime)
				.update()
		} catch {
			// Field already exists. Return early.
			return
		}
		try await QSO.query(on: database)
			.set(\.$modificationDate, to: Date())
			.update()
	}
	
	func revert(on database: Database) async throws {
		try await database.schema("qsos")
			.deleteField("modification_date")
			.update()
	}
}

