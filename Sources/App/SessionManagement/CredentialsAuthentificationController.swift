import Vapor
import Leaf
import Fluent

struct CredentialsAuthentificationController: RouteCollection {

	static let basePath: PathComponent = "credentials"
	static let minimumPasswordLength = 8
	static let maxPasswordLength = 1024

	static let registerTemplate = "register-credentials"
	static let loginTemplate = "login-credentials"
	static let changeTemplate = "credentials-change"

	// Stored in UserCredential
	static let authProviderIdentifier = "credentials-auth"

	struct CredentialView: Content, CommonContentProviding {
		var error: String?
		var accountType: BaseAuthentificationController.RegisterAccountType?
		var callsign: String?
		var showCallsignCheckOverride: Bool = false
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
		return try await req.view.render(Self.registerTemplate, ["common":req.commonContent])
	}

	struct CredentialsRegisterContent: Content, BaseAuthentificationController.RegisterContent {
		var accountType: BaseAuthentificationController.RegisterAccountType?
		var callsign: String
		var overrideCallsignCountryCheck: String?
		var acceptTerms: String
		var password: String
		var password_repeat: String
	}

	func registerPost(req: Request) async throws -> Response {
		let registerContent = try req.content.decode(CredentialsRegisterContent.self)
		let callsign = registerContent.callsign

		let baseValidationResult = try await BaseAuthentificationController.commonRegistrationValidation(req: req)
		let normalizedCallSign: String
		var showCallsignCheckOverride = false
		switch baseValidationResult {
		case .callsignCountryCheck(let error):
			showCallsignCheckOverride = true
			fallthrough
		case .error(let error):
			let viewResponse: Response = try await req.view.render(Self.registerTemplate, CredentialView(error: error, accountType: registerContent.accountType, callsign: callsign, showCallsignCheckOverride: showCallsignCheckOverride, common: req.commonContent)).encodeResponse(for: req)
			return viewResponse
		case .success(normalizedCall: let call):
			normalizedCallSign = call
			break
		}
		let passwordLength = registerContent.password.count
		if passwordLength < Self.minimumPasswordLength || passwordLength > Self.maxPasswordLength {
			let error = passwordLength < Self.minimumPasswordLength ? "Password must be at least \(Self.minimumPasswordLength) characters long." : "Password is too long, what are you trying to do?"
			return try await req.view.render(Self.registerTemplate, CredentialView(error:error, accountType: registerContent.accountType, callsign: callsign, common: req.commonContent)).encodeResponse(for: req)
			
		}

		if registerContent.password != registerContent.password_repeat {
			let viewResponse: Response = try await req.view.render(Self.registerTemplate, CredentialView(error: "Passwords do not match.", accountType: registerContent.accountType, callsign: callsign, common: req.commonContent)).encodeResponse(for: req)
			return viewResponse
		}

		guard let accountType = registerContent.accountType else {
			let viewResponse: Response = try await req.view.render(Self.registerTemplate, CredentialView(error: "Account type needs to be selected.", accountType: registerContent.accountType, callsign: callsign, common: req.commonContent)).encodeResponse(for: req)
			return viewResponse
		}

		return try await BaseAuthentificationController.createUser(on: req, callsign: normalizedCallSign, accountType: accountType) { newUserModel in
			try await UserCredential(userId: newUserModel.requireID(),
									 authProvider: Self.authProviderIdentifier,
									 loginIdentifier: normalizedCallSign,
									 additionalStorage: try Bcrypt.hash(registerContent.password)
			).save(on: req.db)
		}
	}

	func login(req: Request) async throws -> View {
		try await req.view.render(Self.loginTemplate, CredentialView(common:req.commonContent))
	}

	func loginPost(req: Request) async throws -> Response {
		struct CredentialsLoginContent: Content {
			var accountType: BaseAuthentificationController.RegisterAccountType?
			var callsign: String
			var password: String
		}

		let credentials = try req.content.decode(CredentialsLoginContent.self)

		let callsign = normalizedCallsign(credentials.callsign)

		guard let userCredential = try await UserCredential.query(on: req.db)
			.filter(UserCredential.self, \.$loginIdentifier == callsign)
			.filter(\.$authProvider == Self.authProviderIdentifier)
			.with(\.$user, { query in query.with(\.$callsign) })
			.first() else {
			let viewResponse: Response = try await req.view.render(Self.loginTemplate, CredentialView(error: "Unknown callsign. Did you use a different auth provider during registration?", callsign: callsign, common: req.commonContent)).encodeResponse(for: req)
			return viewResponse
		}

		guard let hashedPassword = userCredential.additionalStorage, !hashedPassword.isEmpty else {
			let viewResponse: Response = try await req.view.render(Self.loginTemplate, CredentialView(error: "Callsign did not use password authentification during registration.", callsign: callsign, common: req.commonContent)).encodeResponse(for: req)
			return viewResponse
		}

		guard let match = try? Bcrypt.verify(credentials.password, created: hashedPassword), match else {
			let viewResponse: Response = try await req.view.render(Self.loginTemplate, CredentialView(error: "Password does not match.", callsign: callsign, common: req.commonContent)).encodeResponse(for: req)
			return viewResponse
		}

		req.auth.login(userCredential.user)
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


		let credential = try await UserCredential.query(on: req.db).filter(\.$user.$id == user.requireID()).filter(\.$authProvider == Self.authProviderIdentifier).first()

		guard let credential, let hashedPassword = credential.additionalStorage, !hashedPassword.isEmpty else {
			return try await req.view.render(Self.changeTemplate, CredentialView(success: nil, error: "Callsign did not use password authentification during registration.", common: req.commonContent))
		}

		guard let match = try? Bcrypt.verify(content.current_password, created: hashedPassword), match else {
			return try await req.view.render(Self.changeTemplate, CredentialView(success: nil, error: "Old password does not match.", common: req.commonContent))
		}

		credential.additionalStorage = try Bcrypt.hash(content.password)

		try await credential.save(on: req.db)

		return try await req.view.render(Self.changeTemplate, CredentialView(success: "Successfully updated password.", error: nil, common: req.commonContent))
	}

}
