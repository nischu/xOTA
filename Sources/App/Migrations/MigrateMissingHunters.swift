import Fluent

// TODO: this can be removed before the next OSS release, since the schema is incompatible anyways and external users likely to set up a new system anyways.
struct MigrateMissingHunters: AsyncMigration {
	func prepare(on database: Database) async throws {

		let users: [UserModel] = try await UserModel.query(on: database).with(\.$callsign).all()

		// Update existing QSOs to add users that were created after QSO logging before the feature was in place on user creation.
		for user in users {
			let userId = try user.requireID()
			let callsign = user.callsign.callsign
			try await QSO.query(on: database)
				.filter(\.$call, .equal, callsign)
				.filter(\.$hunter.$id, .equal, nil)
				.set(\.$hunter.$id, to: userId)
				.update()
			try await QSO.query(on: database)
				.filter(\.$contactedOperator, .equal, callsign)
				.filter(\.$contactedOperatorUser.$id, .equal, nil)
				.set(\.$contactedOperatorUser.$id, to: userId)
				.update()
		}
	}

	func revert(on database: Database) async throws {
	}
}
