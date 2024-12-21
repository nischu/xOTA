import NIOSSL
import Fluent
import FluentSQLiteDriver
import QueuesFluentDriver
import Leaf
import Vapor

// configures your application
public func configure(_ app: Application) async throws {
	// uncomment to serve files from /Public folder
	app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
	
	// TODO: read from config
	app.namingTheme = NamingTheme(
		activityName: "TOTA at 38C3",
		adifSIG: "TOTA",
		referenceSlug: "t",
		referenceSingular: "Toilet",
		referencePlural: "Toilets")


	if app.environment == .testing {
		app.authentificationConfiguration = AuthentificationConfiguration(cccHUBEnabled: false, darcSSOEnabled: false, userPassEnabled: true)
	} else {
		let userPassEnabled = (Environment.get("USER_PASS_ENABLED") as? NSString)?.boolValue ?? false
		let darcSSO = Environment.get("DARC_SSO_AUTH_CALLBACK") != nil
		app.authentificationConfiguration = AuthentificationConfiguration(cccHUBEnabled: true, darcSSOEnabled:darcSSO, userPassEnabled: userPassEnabled)
	}

	app.views.use(.leaf)
	app.leaf.tags["urlEncode"] = URLEncodeHostAllowedTag()

	if app.environment == .testing {
		app.databases.use(.sqlite(.memory), as: .sqlite)
	} else {
		app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)
	}

	app.migrations.add(CreateReference())
	app.migrations.add(CreateUser())
	app.migrations.add(CreateUserRole())
	app.migrations.add(CreateCallsign())
	app.migrations.add(CreateQso())
	app.migrations.add(CreateAward())
	app.migrations.add(CreateUserCredential())
	app.migrations.add(CreateSpot())
	// TODO: can be removed before the next OSS release
	app.migrations.add(MigrateMissingHunters())
	app.migrations.add(ModifyQsoAddModificationDate())
	app.migrations.add(MigrateUserCredentials())

#if DEBUG
	app.migrations.add(SeedSampleData())
#else
	app.migrations.add(Seed38C3Data())
#endif

	// Session handling
	app.migrations.add(SessionRecord.migration)

	app.sessions.use(.fluent(.sqlite))

	// Queues
	app.migrations.add(JobMetadataMigrate())
	app.queues.use(.fluent(.sqlite))

#if DEBUG
	let secureCookie = false
#else
	let secureCookie = true
#endif
	app.sessions.configuration.cookieFactory = { sessionID in
		return HTTPCookies.Value(
			string: sessionID.string,
			expires: Date(
				timeIntervalSinceNow: 60 * 60 * 24 // one day
			),
			maxAge: nil,
			domain: nil,
			path: "/",
			isSecure: secureCookie,
			isHTTPOnly: secureCookie,
			sameSite: .lax
		)
	}

	let webSockets = WebSocketManager()
	app.lifecycle.use(webSockets)
	app.webSocketManager = webSockets

	let webSocketsSpots = WebSocketManager()
	app.lifecycle.use(webSocketsSpots)
	app.webSocketManagerSpots = webSocketsSpots

	app.middleware.use(app.sessions.middleware)
	app.middleware.use(CustomDatabaseSessionAuthenticator(databaseID: .sqlite))

	app.asyncCommands.use(MakeAdminCommand(), as: MakeAdminCommand.name)
	app.asyncCommands.use(ResetPasswordCommand(), as: ResetPasswordCommand.name)


	// Queues configuration
	app.queues.configuration.refreshInterval = .seconds(10)
	app.queues.configuration.workerCount = 1 // serial queue processing
	app.queues.add(RenderAward())
	app.queues.add(DeleteAwardData())
	app.queues.add(CheckAwardElegibilityUser())
	app.queues.add(AwardCheckScheduler())
	try app.queues.startInProcessJobs(on: .default)

	app.queues.schedule(UpdateSpots()).minutely().at(13)
	try app.queues.startScheduledJobs()

	app.lifecycle.use(AwardCheckSchedulerLifecycle())

	// General Awards:
	app.awardCheckers.append(AwardCheckerActivatedAll())
	app.awardCheckers.append(AwardCheckerHuntedAll())

	// 38C3 specific:
	app.awardCheckers.append(AwardCheckerBasementConnection())
	app.awardCheckers.append(AwardCheckerInHouseDX())

	// register routes
	try routes(app)
}

extension Environment {
	static var configure: Environment { .custom(name: "configure") }
}
