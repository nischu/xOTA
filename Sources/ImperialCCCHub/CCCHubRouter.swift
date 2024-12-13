import Vapor
import Foundation
import ImperialCore
import PKCE

public class CCCHubRouter: FederatedServiceRouter {


	public let baseURL: String
	public let tokens: FederatedServiceTokens
	public let callbackCompletion: (Request, String) throws -> (EventLoopFuture<ResponseEncodable>)
	public var scope: [String] = [ ]
	public var requiredScopes: [String] = [ ]
	public let callbackURL: String
	public let accessTokenURL: String
	public var service: OAuthService = .cccHub
	public let callbackHeaders = HTTPHeaders([("Content-Type", "application/x-www-form-urlencoded")])
	//	public var codeKey: String = "access_token"

	private static let verifierKey = "ccchub-verifier"

	private func providerUrl(path: String) -> String {
		return self.baseURL.finished(with: "/") + path
	}

	public required init(callback: String, completion: @escaping (Request, String) throws -> (EventLoopFuture<ResponseEncodable>)) throws {
		let auth = try CCCHubAuth()
		self.tokens = auth
		self.baseURL = "https://\(auth.domain)"
		self.accessTokenURL = baseURL.finished(with: "/") + "token/"
		self.callbackURL = callback
		self.callbackCompletion = completion
	}

	public func authURL(_ request: Request) throws -> String {
		let path="authorize/"


		let verifier = try generateCodeVerifier()
		let challenge = try generateCodeChallenge(for: verifier)
		request.session.data[Self.verifierKey] = verifier

		// See https://www.rfc-editor.org/rfc/rfc7636
		var params=[
			"response_type=code",
			"client_id=\(self.tokens.clientID)",
			"redirect_uri=\(self.callbackURL)",
			"code_challenge=\(challenge)",
			"code_challenge_method=S256",
		]

		let allScopes = self.scope + self.requiredScopes
		let scopeString = allScopes.joined(separator: " ").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
		if let scopes = scopeString {
			params += [ "scope=\(scopes)" ]
		}

		let rtn = self.providerUrl(path: path + "?" + params.joined(separator: "&"))
		return rtn
	}

	public func fetchToken(from request: Request) throws -> EventLoopFuture<String> {
		let code: String
		if let queryCode: String = try request.query.get(at: codeKey) {
			code = queryCode
		} else if let error: String = try request.query.get(at: errorKey) {
			throw Abort(.badRequest, reason: error)
		} else {
			throw Abort(.badRequest, reason: "Missing 'code' key in URL query")
		}

		let body = try callbackBody(with: code, for: request)
		let url = URI(string: accessTokenURL)

		return body.encodeResponse(for: request)
			.map { $0.body.buffer }
			.flatMap { buffer in
				return request.client.post(url, headers: self.callbackHeaders) { $0.body = buffer }
			}.flatMapThrowing { response in
//				let refreshToken = try response.content.get(String.self, at: ["refresh_token"])
//				request.session.setRefreshToken(refreshToken)

				return try response.content.get(String.self, at: ["access_token"])
			}
	}

	public func callbackBody(with code: String, for request: Request) throws -> ResponseEncodable {

		guard let verifier = request.session.data[Self.verifierKey] else {
			throw Abort(.badRequest, reason: "Missing verifier.")
		}
		request.session.data[Self.verifierKey] = nil
		return CCCHubCallbackBody(clientId: self.tokens.clientID,
						   clientSecret: self.tokens.clientSecret,
						   code: code,
						   redirectURI: self.callbackURL,
						   codeVerifier: verifier
		)
	}

	public func callbackBody(with code: String) -> Vapor.ResponseEncodable {
		assertionFailure("This should not be called, only implemented to conform to the protocol.")
		return CCCHubCallbackBody(clientId: self.tokens.clientID,
								  clientSecret: self.tokens.clientSecret,
								  code: code,
								  redirectURI: self.callbackURL,
								  codeVerifier: ""
		)
	}
}
