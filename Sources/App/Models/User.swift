
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
}
