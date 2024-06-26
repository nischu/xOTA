import NIOSSL
import Fluent
import FluentSQLiteDriver
import Leaf
import Vapor

// configures your application
public func configure(_ app: Application) async throws {
	// uncomment to serve files from /Public folder
	app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
	
	// TODO: read from config
	app.namingTheme = NamingTheme(referenceSlug: "t", referenceSingular: "Toilet", referencePlural: "Toilets")
	app.authentificationConfiguration = AuthentificationConfiguration(cccHUBEnabled: true, userPassEnabled: false)


	app.views.use(.leaf)
	app.leaf.tags["urlEncode"] = URLEncodeHostAllowedTag()

	app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)

	app.migrations.add(CreateReference())
	app.migrations.add(CreateUser())
	app.migrations.add(CreateUserRole())
	app.migrations.add(CreateQso())

#if DEBUG
	app.migrations.add(SeedSampleData())
#else
	app.migrations.add(Seed37C3Data())
#endif

	// Session handling
	app.migrations.add(SessionRecord.migration)
	app.sessions.use(.fluent(.sqlite))

	app.sessions.configuration.cookieFactory = { sessionID in
		return HTTPCookies.Value(
			string: sessionID.string,
			expires: Date(
				timeIntervalSinceNow: 60 * 60 * 24 // one day
			),
			maxAge: nil,
			domain: nil,
			path: "/",
			isSecure: true,
			isHTTPOnly: true,
			sameSite: .lax
		)
	}


	app.middleware.use(app.sessions.middleware)
	app.middleware.use(UserModel.sessionAuthenticator())

	app.asyncCommands.use(MakeAdminCommand(), as: MakeAdminCommand.name)

	// register routes
	try routes(app)
}

extension Environment {
	static var configure: Environment { .custom(name: "configure") }
}
