import Vapor
import ImperialCore
import ImperialCCCHub

struct CCCHubAuthController: RouteCollection {

	static let registerCallSignKey = "ccc-hub-register-callsign"
	static let registerAccountType = "ccc-hub-register-account-type"
	static let authStartSSOPath = "/ccc-hub/ccc-hub-auth"
	static let basePath: PathComponent = "ccc-hub"

	static let registerTemplate = "ccc-hub-register"

	func boot(routes: RoutesBuilder) throws {
		let authCallbackPath = try Environment.get("CCCHUB_AUTH_CALLBACK").value(or: ImperialError.missingEnvVar("CCCHUB_AUTH_CALLBACK"))

		let grouped = routes.grouped(Self.basePath)

		// Setup OAuth with CCC Hub
		try routes.oAuth(from: CCCHub.self, authenticate: Self.authStartSSOPath, callback: authCallbackPath, scope: [ "38c3_attendee" ]) { (request, token) in
			return request.client.get(URI(stringLiteral: "https://api.events.ccc.de/congress/2024/me"), headers: HTTPHeaders([("Authorization", "Bearer \(token)")])).flatMap { response in
				// Manually remove OAuth access token we only need it for one request and don't want to hang onto it.
				request.session.data["access_token"] = nil

				guard let authenticated = try? response.content.get(Bool.self, at: ["authenticated"]),
					  let username = try? response.content.get(String.self, at: ["username"]),
					  authenticated == true
				else {
					return request.eventLoop.future(request.redirect(to: "/"))
				}
				

				return UserModel.query(on: request.db).filter(\.$ccchubUser, .equal, username).with(\.$callsign).first().map { userModel in
					defer {
						// Remove any registration callsign
						request.session.data[Self.registerCallSignKey] = nil
						request.session.data[Self.registerAccountType] = nil
					}
					if let userModel {
						request.auth.login(userModel)
						return request.eventLoop.future(request.redirect(to: "/"))
					} else {
						// We check if we are coming from the registration flow.
						guard let callsign = request.session.data[Self.registerCallSignKey],
							  let accountTypeString = request.session.data[Self.registerAccountType],
							  let accountType = BaseAuthentificationController.RegisterAccountType(rawValue: accountTypeString)
						else {
							return request.eventLoop.future(request.redirect(to: "/register"))
						}

						return request.eventLoop.makeFutureWithTask {
							return try await BaseAuthentificationController.createUser(on: request, callsign: callsign, accountType: accountType) { newUserModel in
								newUserModel.ccchubUser = username
							}
						}
					}
				}
			}
		}

		grouped.get("register") { req async throws in
			return try await req.view.render(Self.registerTemplate, ["common" : req.commonContent])
		}
		
		grouped.post("register") { req async throws -> Response in
			struct CCCRegisterContent: BaseAuthentificationController.RegisterContent {
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

			let registerContent = try req.content.decode(CCCRegisterContent.self)
			let accountType = registerContent.accountType
			let callsign = registerContent.callsign

			let baseValidationResult = try await BaseAuthentificationController.commonRegistrationValidation(req: req)
			switch baseValidationResult {
			case .success(normalizedCall: let normalizedCallsign):
				req.session.data[Self.registerCallSignKey] = normalizedCallsign
				req.session.data[Self.registerAccountType] = accountType?.rawValue
				let redirectResponse:Response = req.redirect(to: Self.authStartSSOPath)
				return redirectResponse
			case .error(let error):
				let viewResponse: Response = try await req.view.render(Self.registerTemplate, RegisterView(error: error, accountType: accountType, callsign: callsign, common: req.commonContent)).encodeResponse(for: req)
				return viewResponse
			}
		}

		grouped.get("login") { req async throws in
			return req.redirect(to: Self.authStartSSOPath)
		}
	}
}
