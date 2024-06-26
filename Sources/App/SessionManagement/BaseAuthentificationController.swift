import Vapor

struct AuthentificationConfiguration: Codable {
	var cccHUBEnabled: Bool
	var userPassEnabled: Bool
}

struct AuthentificationConfigurationKey: StorageKey {
	typealias Value = AuthentificationConfiguration
}

extension Application {

	var authentificationConfiguration: AuthentificationConfiguration {
		get {
			self.storage[AuthentificationConfigurationKey.self] ?? AuthentificationConfiguration(cccHUBEnabled: false, userPassEnabled: false)
		}
		set {
			self.storage[AuthentificationConfigurationKey.self] = newValue
		}
	}
}


protocol RegisterContent: Content {
    var callsign: String { get }
    var acceptTerms: String { get }
}

struct BaseAuthentificationController: RouteCollection {


	struct AuthentificationContext: Codable {
		var common: CommonContent
		var configuration: AuthentificationConfiguration
	}

	let configuration: AuthentificationConfiguration

	enum ValidationResponse {
		case success(normalizedCall: String)
		case error(_ error: String)
	}

	static func commonRegistrationValidation(req: Request) async throws -> ValidationResponse {
		struct BaseRegisterContent: RegisterContent, Validatable {
			var callsign: String
			var acceptTerms: String

			static func validations(_ validations: inout Validations) {
				validations.add("callsign", as: String.self, is: .callsign)
			}
		}

		let registerContent = try req.content.decode(BaseRegisterContent.self)
		guard registerContent.acceptTerms == "on" else {
			return .error("You need accept the terms to register.")
		}

		do {
			try BaseRegisterContent.validate(content: req)
		} catch {
			return .error("Callsign not valid.")
		}
		let normalizedCallsign = normalizedCallsign(registerContent.callsign)
		guard try await UserModel.query(on: req.db).field(\.$id).filter(\.$callsign, .equal, normalizedCallsign).first() == nil else {
			return .error("Callsign already registered.")
		}
		return .success(normalizedCall: normalizedCallsign)
	}

	func boot(routes: RoutesBuilder) throws {

		routes.get("register") { req async throws in
			return try await req.view.render("base-register", AuthentificationContext(common: req.commonContent, configuration: configuration))
		}

		routes.get("login") { req async throws in
			try await req.view.render("base-login", AuthentificationContext(common: req.commonContent, configuration: configuration))
		}

		routes.get("logout") { req async throws in
			req.auth.logout(UserModel.self)
			return req.redirect(to: "/")
		}
		
		if configuration.cccHUBEnabled {
			try CCCHubAuthController().boot(routes: routes)
		}
		if configuration.userPassEnabled {
			try CredentialsAuthentificationController().boot(routes: routes)
		}
	}
}
