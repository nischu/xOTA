import Fluent
import Vapor

struct CustomDatabaseSessionAuthenticator<User: UserModel>: SessionAuthenticator
	where User: SessionAuthenticatable, User: Model, User.SessionID == User.IDValue
{
	let databaseID: DatabaseID?

	func authenticate(sessionID: User.SessionID, for request: Request) -> EventLoopFuture<Void> {
		User.find(sessionID, on: request.db(self.databaseID)).map {
			if let user = $0 {
				request.auth.login(user)
			}
		}
	}
}
