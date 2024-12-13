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

	enum RegisterAccountType: String, RawRepresentable, Codable {
		case licensed
		case unlicensed
	}

	protocol RegisterContent: Content {
		var accountType: RegisterAccountType? { get }
		var callsign: String { get }
		var acceptTerms: String { get }
	}

	static func commonRegistrationValidation(req: Request) async throws -> ValidationResponse {
		struct BaseRegisterContent: RegisterContent, Validatable {
			var accountType: RegisterAccountType?
			var callsign: String
			var acceptTerms: String

			static func validations(_ validations: inout Validations) {
				validations.add("accountType", as: RegisterAccountType?.self, is: !.nil, customFailureDescription: "You need to select an account type.")
				validations.add("callsign", as: String.self, is: .relaxedCallsign)
			}
		}

		let registerContent = try req.content.decode(BaseRegisterContent.self)
		guard registerContent.acceptTerms == "on" else {
			return .error("You need accept the terms to register.")
		}

		do {
			try BaseRegisterContent.validate(content: req)
		} catch let validationsError as ValidationsError {
			return .error(validationsError.description)
		}

		if registerContent.accountType == .licensed,
		   Validator.callsign.validate(registerContent.callsign).isFailure {
			return .error("Callsign not valid.")
		}
		let normalizedCallsign = normalizedCallsign(registerContent.callsign)
		guard try await Callsign.query(on: req.db).field(\.$id).filter(\.$callsign, .equal, normalizedCallsign).first() == nil else {
			return .error("Callsign already registered.")
		}
		return .success(normalizedCall: normalizedCallsign)
	}

	static func createUser(on req: Request, callsign: String, accountType: RegisterAccountType, createCredential: @escaping (UserModel) async throws -> ()) async throws -> Response {

		let callsignKind: Callsign.CallsignKind = {
			switch accountType {
			case .licensed:
				return .licensed
			case .unlicensed:
				return .unlicensed
			}
		}()


		let newUserModel = try await UserModel.createUser(with: callsign, kind: callsignKind, on: req.db)
		try await createCredential(newUserModel)
		let userId = try newUserModel.requireID()

		// Update existing QSOs to add the newly created hunter or contacted operator if needed.
		try await req.db.transaction { db in
			try await QSO.query(on: db)
				.filter(\.$call, .equal, callsign)
				.filter(\.$hunter.$id, .equal, nil)
				.set(\.$hunter.$id, to: userId)
				.update()
			try await QSO.query(on: db)
				.filter(\.$contactedOperator, .equal, callsign)
				.filter(\.$contactedOperatorUser.$id, .equal, nil)
				.set(\.$contactedOperatorUser.$id, to: userId)
				.update()
		}

		req.auth.login(newUserModel)
		return req.redirect(to: "/")
	}

	func boot(routes: RoutesBuilder) throws {

		routes.get("register") { req async throws in
			return try await req.view.render("register-entry", AuthentificationContext(common: req.commonContent, configuration: configuration))
		}

		routes.get("login") { req async throws in
			try await req.view.render("login-entry", AuthentificationContext(common: req.commonContent, configuration: configuration))
		}

		routes.get("logout") { req async throws in
			req.auth.logout(UserModel.self)
			req.session.destroy()
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
