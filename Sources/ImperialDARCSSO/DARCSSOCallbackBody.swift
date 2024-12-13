import Vapor

struct DARCSSOCallbackBody: Content {
	let clientId: String
	let clientSecret: String
	let code: String
	let redirectURI: String
	let grantType: String = "authorization_code"
	let state: String
	let codeVerifier: String
	static var defaultContentType: HTTPMediaType = .urlEncodedForm

	enum CodingKeys: String, CodingKey {
		case clientId = "client_id"
		case clientSecret = "client_secret"
		case code = "code"
		case redirectURI = "redirect_uri"
		case grantType = "grant_type"
		case state = "state"
		case codeVerifier = "code_verifier"
	}
}
