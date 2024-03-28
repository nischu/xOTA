import Vapor

final class GuardUserRoleMiddleware: Middleware
{
	/// Error to throw when guard fails.
	private let error: Error
	private let role: UserRoleModel.SpecialRole

	/// Creates a new `GuardUserRoleMiddleware`.
	///
	/// - parameters:
	///     - type: `SpecialRole` type required.
	///     - error: `Error` to throw if the user does not have the role.
	internal init(_ role: UserRoleModel.SpecialRole, throwing error: Error) {
		self.role = role
		self.error = error
	}

	public func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		guard let user = request.auth.get(UserModel.self) else {
			return request.eventLoop.makeFailedFuture(self.error)
		}
		let roles = user.$specialRoles.get(on: request.db)

		return roles.flatMap { roles in
			guard roles.first(where: { $0.role == self.role }) != nil else {
				return request.eventLoop.makeFailedFuture(self.error)
			}
			return next.respond(to: request)
		}
	}
}
