import Vapor
import ImperialCore
import ImperialCCCHub

struct CCCHubAuthController: RouteCollection {

	static let registerCallSignKey = "ccc-hub-register-callsign"
	static let registerAccountType = "ccc-hub-register-account-type"
	static let authStartSSOPath = "/ccc-hub/ccc-hub-auth"
	static let basePath: PathComponent = "ccc-hub"

	static let registerTemplate = "ccc-hub-register"

	// Stored in UserCredential
	static let authProviderIdentifier = "ccc-hub"

	func boot(routes: RoutesBuilder) throws {
		let baseSSOAuthController = BaseSSOAuthController(ssoServiceName: "CCC Hub SSO",
														  ssoBasePath: Self.basePath,
														  authStartSSOPath: Self.authStartSSOPath,
														  registerCallSignKey: Self.registerCallSignKey,
														  registerAccountTypeKey: Self.registerAccountType)
		try routes.register(collection: baseSSOAuthController)

		let authCallbackPath = try Environment.get("CCCHUB_AUTH_CALLBACK").value(or: ImperialError.missingEnvVar("CCCHUB_AUTH_CALLBACK"))

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
				
				let userCredential = UserCredential.query(on: request.db)
					.filter(\.$loginIdentifier, .equal , username)
					.filter(\.$authProvider, .equal, Self.authProviderIdentifier)
					.with(\.$user) { query in query.with(\.$callsign) }
					.first()

				return userCredential.map { credential in
					defer {
						// Remove any registration callsign
						request.session.data[Self.registerCallSignKey] = nil
						request.session.data[Self.registerAccountType] = nil
					}
					// Existing user?
					if let credential {
						// Sign in
						request.auth.login(credential.user)
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
								try await UserCredential(userId: newUserModel.requireID(),
														 authProvider: Self.authProviderIdentifier,
														 loginIdentifier: username,
														 additionalStorage: nil
								).save(on: request.db)
							}
						}
					}
				}
			}
		}
	}
}
