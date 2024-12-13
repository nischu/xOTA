import Vapor

struct BaseSSOAuthController: RouteCollection {
	let ssoServiceName: String
	let ssoBasePath: PathComponent
	let authStartSSOPath: String

	let registerCallSignKey: String
	let registerAccountTypeKey: String

	static let registerTemplate = "register-sso"

	func boot(routes: RoutesBuilder) throws {
		let grouped = routes.grouped(self.ssoBasePath)

		grouped.get("register", use: register(req:))
		grouped.post("register", use: registerPost(req:))
		grouped.get("login", use: login(req:))
	}

	func register(req: Request) async throws -> View {
		struct Context: Content {
			let serviceName: String
			let formPath: String
			let common: CommonContent
		}
		return try await req.view.render(Self.registerTemplate, Context(serviceName: ssoServiceName, formPath:req.url.path, common: req.commonContent))
	}

	func registerPost(req: Request) async throws -> Response {
		struct SSORegisterContent: BaseAuthentificationController.RegisterContent {
			var accountType: BaseAuthentificationController.RegisterAccountType?
			var callsign: String
			var acceptTerms: String
		}
		struct RegisterView: Content, CommonContentProviding {
			var error: String
			var accountType: BaseAuthentificationController.RegisterAccountType?
			var callsign: String
			let common: CommonContent
		}

		let registerContent = try req.content.decode(SSORegisterContent.self)
		let accountType = registerContent.accountType
		let callsign = registerContent.callsign

		let baseValidationResult = try await BaseAuthentificationController.commonRegistrationValidation(req: req)
		switch baseValidationResult {
		case .success(normalizedCall: let normalizedCallsign):
			req.session.data[registerCallSignKey] = normalizedCallsign
			req.session.data[registerAccountTypeKey] = accountType?.rawValue
			let redirectResponse:Response = req.redirect(to: self.authStartSSOPath)
			return redirectResponse
		case .error(let error):
			let viewResponse: Response = try await req.view.render(Self.registerTemplate, RegisterView(error: error, accountType: accountType, callsign: callsign, common: req.commonContent)).encodeResponse(for: req)
			return viewResponse
		}
	}

	func login(req: Request) async throws -> Response {
		return req.redirect(to: self.authStartSSOPath)
	}

	func registerOrSignin(req: Request, loginIdentifier: String, authProviderIdentifier: String, registerCallsignKey: String, registerAccountTypeKey: String) -> EventLoopFuture<any ResponseEncodable> {
		// Manually remove OAuth access token we only needed it for one request and don't want to hang onto it.
		req.session.data["access_token"] = nil

		let userCredential = UserCredential.query(on: req.db)
			.filter(\.$loginIdentifier, .equal , loginIdentifier)
			.filter(\.$authProvider, .equal, authProviderIdentifier)
			.with(\.$user) { query in query.with(\.$callsign) }
			.first()

		return userCredential.map { credential in
			defer {
				// Remove any registration callsign
				req.session.data[registerCallSignKey] = nil
				req.session.data[registerAccountTypeKey] = nil
			}
			// Existing user?
			if let credential {
				// Sign in
				req.auth.login(credential.user)
				return req.eventLoop.future(req.redirect(to: "/"))
			} else {
				// We check if we are coming from the registration flow.
				guard let callsign = req.session.data[registerCallSignKey],
					  let accountTypeString = req.session.data[registerAccountTypeKey],
					  let accountType = BaseAuthentificationController.RegisterAccountType(rawValue: accountTypeString)
				else {
					return req.eventLoop.future(req.redirect(to: "/register"))
				}

				return req.eventLoop.makeFutureWithTask {
					return try await BaseAuthentificationController.createUser(on: req, callsign: callsign, accountType: accountType) { newUserModel in
						try await UserCredential(userId: newUserModel.requireID(),
												 authProvider: authProviderIdentifier,
												 loginIdentifier: loginIdentifier,
												 additionalStorage: nil
						).save(on: req.db)
					}
				}
			}
		}

	}
}
