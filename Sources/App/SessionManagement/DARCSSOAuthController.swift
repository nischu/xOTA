import Vapor
import ImperialCore
import ImperialDARCSSO

struct DARCSSOAuthController: RouteCollection {

	static let registerCallSignKey = "darc-sso-register-callsign"
	static let registerAccountType = "darc-sso-register-account-type"
	static let authStartSSOPath = "/darc-sso/start-auth"
	static let basePath: PathComponent = "darc-sso"

	static let registerTemplate = "ccc-hub-register"

	static let authProviderIdentifier = "darc-sso"

	func boot(routes: RoutesBuilder) throws {

		let baseSSOAuthController = BaseSSOAuthController(ssoServiceName: "DARC SSO",
														  ssoBasePath: Self.basePath,
														  authStartSSOPath: Self.authStartSSOPath,
														  registerCallSignKey: Self.registerCallSignKey,
														  registerAccountTypeKey: Self.registerAccountType)
		try routes.register(collection: baseSSOAuthController)


		let authCallbackPath = try Environment.get("DARC_SSO_AUTH_CALLBACK").value(or: ImperialError.missingEnvVar("DARC_SSO_AUTH_CALLBACK"))

		// Setup OAuth with DARC SSO
		try routes.oAuth(from: DARCSSO.self, authenticate: Self.authStartSSOPath, callback: authCallbackPath, scope: [ "callsign" ]) { (request, token) in

			return request.client.get(URI(stringLiteral: "https://sso.darc.de/module.php/oidc/userinfo.php"), headers: HTTPHeaders([("Authorization", "Bearer \(token)")])).flatMap { response in

				// {\"callsign\":\"$CALL\",\"sub\":\"$DARC_MEMBERID\"}"
				guard let sub = try? response.content.get(String.self, at: ["sub"]),
					  let callsign = try? response.content.get(String.self, at: ["callsign"]),
					  !sub.isEmpty, !callsign.isEmpty
				else {
					return request.eventLoop.future(request.redirect(to: "/"))
				}

				return baseSSOAuthController.registerOrSignin(req: request, loginIdentifier: sub, authProviderIdentifier: Self.authProviderIdentifier, registerCallsignKey: Self.registerCallSignKey, registerAccountTypeKey: Self.registerAccountType)
			}
		}
	}
}
