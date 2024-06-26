import Vapor
import Leaf

struct CredentialsAuthentificationController: RouteCollection {

	static let basePath: PathComponent = "credentials"
	static let minimumPasswordLength = 8
	static let maxPasswordLength = 1024

	static let registerTemplate = "credentials-register"
	static let loginTemplate = "credentials-login"
	static let changeTemplate = "credentials-change"

	struct CredentialView: Content, CommonContentProviding {
		var error: String?
		var callsign: String?
		let common: CommonContent
	}


	func boot(routes: RoutesBuilder) throws {

		let grouped = routes.grouped(Self.basePath)

		grouped.get("register", use: register)
		grouped.post("register", use: registerPost)

		grouped.get("login", use: login)
		grouped.post("login", use: loginPost)

		grouped.get("change", use: change)
		grouped.post("change", use: changePost)

	}

	func register(req: Request) async throws -> View {
		return try await req.view.render(Self.registerTemplate, req.commonContent)
	}

	func registerPost(req: Request) async throws -> Response {
		struct CredentialsRegisterContent: Content {
			var callsign: String
			var acceptTerms: String
			var password: String
			var password_repeat: String
		}

		let registerContent = try req.content.decode(CredentialsRegisterContent.self)
		let callsign = registerContent.callsign

		let baseValidationResult = try await BaseAuthentificationController.commonRegistrationValidation(req: req)
		let normalizedCallSign: String
		switch baseValidationResult {
		case .error(let error):
			let viewResponse: Response = try await req.view.render(Self.registerTemplate, CredentialView(error: error, callsign: callsign, common: req.commonContent)).encodeResponse(for: req)
			return viewResponse
		case .success(normalizedCall: let call):
			normalizedCallSign = call
			break
		}
		let passwordLength = registerContent.password.count
		if passwordLength < Self.minimumPasswordLength || passwordLength > Self.maxPasswordLength {
			let error = passwordLength < Self.minimumPasswordLength ? "Password must be at least \(Self.minimumPasswordLength) characters long." : "Password is too long, what are you trying to do?"
			return try await req.view.render(Self.registerTemplate, CredentialView(error:error, callsign: callsign, common: req.commonContent)).encodeResponse(for: req)
		}

		if registerContent.password != registerContent.password_repeat {
			let viewResponse: Response = try await req.view.render(Self.registerTemplate, CredentialView(error: "Passwords do not match.", callsign: callsign, common: req.commonContent)).encodeResponse(for: req)
			return viewResponse
		}

		let newUserModel = UserModel(callsign: normalizedCallSign)
		newUserModel.hashedPassword = try Bcrypt.hash(registerContent.password)
		try await newUserModel.save(on: req.db)

		// TODO: update existing QSOs to add the newly created hunter if needed.

		req.auth.login(newUserModel)
		return req.redirect(to: "/")
	}

	func login(req: Request) async throws -> View {
		try await req.view.render(Self.loginTemplate, CredentialView(common:req.commonContent))
	}

	func loginPost(req: Request) async throws -> Response {
		struct CredentialsLoginContent: Content {
			var callsign: String
			var password: String
		}

		let credentials = try req.content.decode(CredentialsLoginContent.self)

		let callsign = normalizedCallsign(credentials.callsign)
		guard let user = try await UserModel.query(on: req.db).field(\.$id).field(\.$hashedPassword).filter(\.$callsign, .equal, callsign).first() else {
			let viewResponse: Response = try await req.view.render(Self.loginTemplate, CredentialView(error: "Unknown callsign.", callsign: callsign, common: req.commonContent)).encodeResponse(for: req)
			return viewResponse
		}

		guard let hashedPassword = user.hashedPassword, !hashedPassword.isEmpty else {
			let viewResponse: Response = try await req.view.render(Self.loginTemplate, CredentialView(error: "Callsign did not use password authentification during registration.", callsign: callsign, common: req.commonContent)).encodeResponse(for: req)
			return viewResponse
		}

		guard let match = try? Bcrypt.verify(credentials.password, created: hashedPassword), match else {
			let viewResponse: Response = try await req.view.render(Self.loginTemplate, CredentialView(error: "Password does not match.", callsign: callsign, common: req.commonContent)).encodeResponse(for: req)
			return viewResponse
		}

		req.auth.login(user)
		return req.redirect(to: "/")
	}


	func change(req: Request) async throws -> View {
		guard req.auth.get(UserModel.self) != nil else {
			throw Abort(.unauthorized)
		}

		return try await req.view.render(Self.changeTemplate, CredentialView(common:req.commonContent))
	}

	func changePost(req: Request) async throws -> View {
		guard let user = req.auth.get(UserModel.self) else {
			throw Abort(.unauthorized)
		}

		struct CredentialsChangeContent: Content {
			var current_password: String
			var password: String
			var password_repeat: String
		}
		let content = try req.content.decode(CredentialsChangeContent.self)

		struct CredentialView: Content {
			var success: String?
			var error: String?
			let common: CommonContent
		}

		let passwordLength = content.password.count
		if passwordLength < Self.minimumPasswordLength || passwordLength > Self.maxPasswordLength {
			let error = passwordLength < Self.minimumPasswordLength ? "Password must be at least \(Self.minimumPasswordLength) characters long." : "Password is too long, what are you trying to do?"
			return try await req.view.render(Self.registerTemplate, CredentialView(success: nil, error:error, common: req.commonContent))
		}

		if content.password != content.password_repeat {
			return try await req.view.render(Self.registerTemplate, CredentialView(success: nil, error: "Passwords do not match.", common: req.commonContent))
		}

		guard let hashedPassword = user.hashedPassword, !hashedPassword.isEmpty else {
			return try await req.view.render(Self.changeTemplate, CredentialView(success: nil, error: "Callsign did not use password authentification during registration.", common: req.commonContent))
		}

		guard let match = try? Bcrypt.verify(content.current_password, created: hashedPassword), match else {
			return try await req.view.render(Self.changeTemplate, CredentialView(success: nil, error: "Old password does not match.", common: req.commonContent))
		}

		user.hashedPassword = try Bcrypt.hash(content.password)
		try await user.save(on: req.db)

		return try await req.view.render(Self.changeTemplate, CredentialView(success: "Successfully updated password.", error: nil, common: req.commonContent))
	}

}
