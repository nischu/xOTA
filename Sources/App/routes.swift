import Fluent
import Vapor

func routes(_ app: Application) throws {
	app.get { req async throws in
		return req.redirect(to: "/rules/")
	}

	let authMiddleware: [Middleware] = [
		UserModel.guardMiddleware(),
	]

	let adminAuthMiddleware: [Middleware] = authMiddleware + [
		GuardUserRoleMiddleware(.admin, throwing: "User does not have admin role.")
	]
	
	let protected = app.grouped(authMiddleware)

	protected.get("me") { req async throws -> String in
		try req.auth.require(UserModel.self).callsign.callsign
	}

	let namingTheme = app.namingTheme
	try app.register(collection: ReferenceController(namingTheme: namingTheme))
	try app.register(collection: UserController(authMiddleware: authMiddleware))
	try app.register(collection: QSOController(authMiddleware: authMiddleware, namingTheme:namingTheme))
	try app.register(collection: StatsController(namingTheme: namingTheme))
	try app.register(collection: AdminController(authMiddleware: adminAuthMiddleware, namingTheme: namingTheme))
	try app.register(collection: APIController(namingTheme: namingTheme))
	if app.environment != .configure {
		try app.register(collection: BaseAuthentificationController(configuration: app.authentificationConfiguration))
	}

	app.get("rules") {req async throws in
		return try await req.view.render("rules", ["common": req.commonContent])
	}


	app.get("impressum") {req async throws in
		return try await req.view.render("impressum", ["common": req.commonContent])
	}

}
