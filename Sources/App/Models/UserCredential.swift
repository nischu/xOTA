import Fluent
import Vapor

final class UserCredential: Model, Content, @unchecked Sendable {
	static let schema = "user_credentials"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "user_id")
	var user: UserModel

	@Field(key: "auth_provider")
	var authProvider: String

	@Field(key: "login_identifier")
	var loginIdentifier: String

	@Field(key: "additional_storage")
	var additionalStorage: String?

	init() { }

	init(userId: UserModel.IDValue, authProvider: String, loginIdentifier: String, additionalStorage: String?) {
		self.$user.id = userId
		self.authProvider = authProvider
		self.loginIdentifier = loginIdentifier
		self.additionalStorage = additionalStorage
	}
}
