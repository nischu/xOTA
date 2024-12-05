
import Fluent
import Vapor

final class UserModel: Model, Content, @unchecked Sendable {
	static let schema = "users"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "primary-callsign")
	var callsign: Callsign

	@Field(key: "ccchub-user")
	var ccchubUser: String?

	@Field(key: "hashed-password")
	var hashedPassword: String?

	@Children(for: \.$user)
	var callsigns: [Callsign]

	@Children(for: \.$activator)
	var activatorQsos: [QSO]

	@Children(for: \.$hunter)
	var hunterQsos: [QSO]

	@Children(for: \.$user)
	var specialRoles: [UserRoleModel]

	init() { }

	init(id: UserModel.IDValue? = nil,
		 callsignId: Callsign.IDValue) {
		self.id = id
		self.$callsign.id = callsignId
	}
}

extension UserModel: SessionAuthenticatable {
	var sessionID: UUID {
		self.id ?? UUID()
	}
}

extension UserModel {

	static func find(
		_ id: UserModel.IDValue?,
		on database: any Database
	) -> EventLoopFuture<UserModel?> {
		guard let id = id else {
			return database.eventLoop.makeSucceededFuture(nil)
		}
		return UserModel.query(on: database)
			.filter(\.$id == id)
			.with(\.$callsign)
			.first()
	}

	static func userFor(callsign: String, on database: any Database) -> EventLoopFuture<UserModel?> {
		return UserModel.query(on: database)
			.join(Callsign.self, on: \UserModel.$id == \Callsign.$user.$id)
			.filter(Callsign.self, \.$callsign == normalizedCallsign(callsign))
			.field(\.$id)
			.first()
	}

	static func createUser(with callsign: String, kind: Callsign.CallsignKind, on database: any Database, additionalModifications: @escaping (UserModel) throws -> () = { _ in }) async throws -> UserModel {
		try await database.transaction { database in
			// Unfortunately we can't really model required 1:1 relationships in FluentKit, hence the user_id field on callsign is not enforced as required.
			// Since the existenced of the id field is trated as insert vs. update indicator we dance a bit back and forth within the transaction.
			let callsign = Callsign(callsign: callsign, kind: kind)
			// Save the callsign to create an ID.
			try await callsign.save(on: database)
			// Now create a user with the callsign id
			let newUserModel = UserModel(callsignId:try callsign.requireID())
			// Apply any additional modifcations in the closure
			try additionalModifications(newUserModel)
			// Save the user model to create an ID.
			try await newUserModel.save(on: database)
			// Add the relationship for callsign to user.
			callsign.$user.id = try newUserModel.requireID()
			try await callsign.update(on: database)
			return newUserModel
		}
	}
}
