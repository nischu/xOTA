import Fluent

struct Seed38C3Data: AsyncMigration {
	func prepare(on database: Database) async throws {

		let references = [
			Reference(title: "T-01", website: "https://38c3.c3nav.de/l/tota-t-01/"),
			Reference(title: "T-02", website: "https://38c3.c3nav.de/l/tota-t-02/"),
			Reference(title: "T-03", website: "https://38c3.c3nav.de/l/tota-t-03/"),
			Reference(title: "T-04", website: "https://38c3.c3nav.de/l/tota-t-04/"),
			Reference(title: "T-11", website: "https://38c3.c3nav.de/l/tota-t-11/"),
			Reference(title: "T-12", website: "https://38c3.c3nav.de/l/tota-t-12/"),
			Reference(title: "T-13", website: "https://38c3.c3nav.de/l/tota-t-13/"),
			Reference(title: "T-14", website: "https://38c3.c3nav.de/l/tota-t-14/"),
			Reference(title: "T-21", website: "https://38c3.c3nav.de/l/tota-t-21/"),
			Reference(title: "T-22", website: "https://38c3.c3nav.de/l/tota-t-22/"),
			Reference(title: "T-23", website: "https://38c3.c3nav.de/l/tota-t-23/"),
			Reference(title: "T-24", website: "https://38c3.c3nav.de/l/tota-t-24/"),
			Reference(title: "T-31", website: "https://38c3.c3nav.de/l/tota-t-31/"),
			Reference(title: "T-32", website: "https://38c3.c3nav.de/l/tota-t-32/"),
			Reference(title: "T-41", website: "https://38c3.c3nav.de/l/tota-t-41/"),
			Reference(title: "T-91", website: "https://38c3.c3nav.de/l/tota-t-91/"),
			Reference(title: "T-92", website: "https://38c3.c3nav.de/l/tota-t-92/"),
		]

		for reference in references {
			try await reference.save(on: database)
		}
	}

	func revert(on database: Database) async throws {
		
	}
}
