
import Fluent
import Vapor

final class UserRoleModel: Model, Content {
	static let schema = "user_roles"

	enum SpecialRole: String, RawRepresentable, Content {
		case admin = "admin"
	}

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "user_id")
	var user: UserModel

	@Field(key: "role")
	var role: SpecialRole

	init() { }

	init(role: SpecialRole) {
		self.role = role
	}
}
