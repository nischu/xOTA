import Vapor

struct CCCHubCallbackBody: Content {
	let clientId: String
	let clientSecret: String
	let code: String
	let redirectURI: String
	let grantType: String = "authorization_code"
	let codeVerifier: String
	static var defaultContentType: HTTPMediaType = .urlEncodedForm

	enum CodingKeys: String, CodingKey {
		case clientId = "client_id"
		case clientSecret = "client_secret"
		case code = "code"
		case redirectURI = "redirect_uri"
		case grantType = "grant_type"
		case codeVerifier = "code_verifier"
	}
}
