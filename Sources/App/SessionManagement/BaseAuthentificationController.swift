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
				validations.add("callsign", as: String.self, is: .count(3...10) && .characterSet(.alphanumerics))
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

	static func createUser(on req: Request, callsign: String, accountType: RegisterAccountType, additionalModifications: @escaping (UserModel) throws -> ()) async throws -> Response {

		let callsignKind: Callsign.CallsignKind = {
			switch accountType {
			case .licensed:
				return .licensed
			case .unlicensed:
				return .unlicensed
			}
		}()


		let newUserModel = try await req.db.transaction { database in
			// Unfortunately we can't really model required 1:1 relationships in FluentKit, hence the user_id field on callsign is not enforced as required.
			// Since the existenced of the id field is trated as insert vs. update indicator we dance a bit back and forth within the transaction.
			let callsign = Callsign(callsign: callsign, kind: callsignKind)
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

		// TODO: update existing QSOs to add the newly created hunter if needed.

		req.auth.login(newUserModel)
		return req.redirect(to: "/")
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
