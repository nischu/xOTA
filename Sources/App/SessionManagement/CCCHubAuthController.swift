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

				guard let authenticated = try? response.content.get(Bool.self, at: ["authenticated"]),
					  let username = try? response.content.get(String.self, at: ["username"]),
					  authenticated == true
				else {
					return request.eventLoop.future(request.redirect(to: "/"))
				}
				return baseSSOAuthController.registerOrSignin(req: request, loginIdentifier: username, authProviderIdentifier: Self.authProviderIdentifier, registerCallsignKey: Self.registerCallSignKey, registerAccountTypeKey: Self.registerAccountType)
			}
		}
	}
}
