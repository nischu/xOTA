
import Fluent
import Vapor

final class UserModel: Model, Content {
	static let schema = "users"

	@ID(key: .id)
	var id: UUID?

	@Field(key: "callsign")
	var callsign: String

	@Field(key: "ccchub-user")
	var ccchubUser: String?

	@Field(key: "hashed-password")
	var hashedPassword: String?

	@Children(for: \.$activator)
	var activatorQsos: [QSO]

	@Children(for: \.$hunter)
	var hunterQsos: [QSO]

	@Children(for: \.$user)
	var specialRoles: [UserRoleModel]

	init() { }

	init(id: UserModel.IDValue? = nil,
		 callsign: String) {
		self.id = id
		self.callsign = callsign
	}
}

extension UserModel: SessionAuthenticatable {
	var sessionID: UUID {
		self.id ?? UUID()
	}
}
