import Vapor
import ImperialCore
import ImperialCCCHub

struct CCCHubAuthController: RouteCollection {

	static let registerCallSignKey = "ccc-hub-register-callsign"
	static let authStartSSOPath = "ccc-hub/ccc-hub-auth"
	static let basePath: PathComponent = "ccc-hub"

	static let registerTemplate = "ccc-hub-register"

	func boot(routes: RoutesBuilder) throws {
		let authCallbackPath = try Environment.get("CCCHUB_AUTH_CALLBACK").value(or: ImperialError.missingEnvVar("CCCHUB_AUTH_CALLBACK"))

		let grouped = routes.grouped(Self.basePath)

		// Setup OAuth with CCC Hub
		try routes.oAuth(from: CCCHub.self, authenticate: Self.authStartSSOPath, callback: authCallbackPath, scope: [ "37c3_attendee" ]) { (request, token) in
			return request.client.get(URI(stringLiteral: "https://api.events.ccc.de/congress/2023/me"), headers: HTTPHeaders([("Authorization", "Bearer \(token)")])).flatMap { response in
				// Manually remove OAuth access token we only need it for one request and don't want to hang onto it.
				request.session.data["access_token"] = nil

				guard let authenticated = try? response.content.get(Bool.self, at: ["authenticated"]),
					  let username = try? response.content.get(String.self, at: ["username"]),
					  authenticated == true
				else {
					return request.eventLoop.future(request.redirect(to: "/"))
				}
				

				return UserModel.query(on: request.db).filter(\.$ccchubUser, .equal, username).first().map { userModel in
					defer {
						// Remove any registration callsign
						request.session.data[Self.registerCallSignKey] = nil
					}
					if let userModel {
						request.auth.login(userModel)
						return request.eventLoop.future(request.redirect(to: "/"))
					} else {
						// We check if we are coming from the registration flow.
						guard let callsign = request.session.data[Self.registerCallSignKey] else {
							return request.eventLoop.future(request.redirect(to: "/register"))
						}
						let newUserModel = UserModel(callsign: callsign)
						newUserModel.ccchubUser = username
						// TODO: update existing QSOs to add the newly created hunter if needed.
//						return request.db.transaction { db in
						return newUserModel.save(on: request.db).map {
//							return newUserModel.save(on: db).flatMapThrowing {
//								let newModelId = try newUserModel.requireID()
//								let future: EventLoopFuture<Void> = QSO.query(on: db).set(\.$hunter.$id, to: newModelId).filter(\.$call, .equal, callsign).filter(\.$hunter.$id, .equal, nil).update()
//								db.eventLoop.f
//							}
						}.map {
							request.auth.login(newUserModel)
							return request.eventLoop.future(request.redirect(to: "/"))
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
				var callsign: String
				var acceptTerms: String
			}
			struct RegisterView: Content, CommonContentProviding {
				var error: String
				var callsign: String
				let common: CommonContent
			}

			let registerContent = try req.content.decode(CCCRegisterContent.self)
			let callsign = registerContent.callsign

			let baseValidationResult = try await BaseAuthentificationController.commonRegistrationValidation(req: req)
			switch baseValidationResult {
			case .success(normalizedCall: let normalizedCallsign):
				req.session.data[Self.registerCallSignKey] = normalizedCallsign
				let redirectResponse:Response = req.redirect(to: Self.authStartSSOPath)
				return redirectResponse
			case .error(let error):
				let viewResponse: Response = try await req.view.render(Self.registerTemplate, RegisterView(error: error, callsign: callsign, common: req.commonContent)).encodeResponse(for: req)
				return viewResponse
			}
		}

		grouped.get("login") { req async throws in
			return req.redirect(to: Self.authStartSSOPath)
		}
	}
}
