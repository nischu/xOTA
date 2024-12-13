import Fluent
import Foundation

// TODO: this can be removed before the next OSS release, since the schema is incompatible anyways and external users likely to set up a new system anyways.
struct MigrateUserCredentials: AsyncMigration {
	func prepare(on database: Database) async throws {
		final class MigrationUserModel: Model, @unchecked Sendable {
			static let schema = "users"

			@ID(key: .id)
			var id: UUID?

			@Parent(key: "primary-callsign")
			var callsign: Callsign

			@Field(key: "ccchub-user")
			var ccchubUser: String?

			@Field(key: "hashed-password")
			var hashedPassword: String?

			init() { }
		}

		let users: [MigrationUserModel]
		do {
			users = try await MigrationUserModel.query(on: database).with(\.$callsign).all()
		} catch {
			print("Failed to fetch users for credential migration. Started with a fresh DB? \(error)")
			users = []
		}
		try await database.transaction { database in
			for user in users {
				let userId = try user.requireID()
				if let cccHubUser = user.ccchubUser {
					try await UserCredential(userId: userId, authProvider: "ccc-hub", loginIdentifier: cccHubUser, additionalStorage: nil).save(on: database)
					user.ccchubUser = nil
				}
				if let password = user.hashedPassword {
					try await UserCredential(userId: userId, authProvider: "credentials-auth", loginIdentifier: user.callsign.callsign, additionalStorage: password).save(on: database)
					user.hashedPassword = nil
				}
				try await user.save(on: database)
			}
		}
	}

	func revert(on database: Database) async throws {
	}

}
