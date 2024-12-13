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
			let common: CommonContent
		}
		return try await req.view.render(Self.registerTemplate, Context(serviceName: ssoServiceName, common: req.commonContent))
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
}
