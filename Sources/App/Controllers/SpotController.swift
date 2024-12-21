import FluentKit
import Vapor


struct SpotController: RouteCollection {
	
	let authMiddleware: [Middleware]
	let namingTheme: NamingTheme

	func boot(routes: any Vapor.RoutesBuilder) throws {
		let api = routes.grouped("api", "spot")

		api.get("all", use: apiSpots(req:)).description("All spots, no auth required. Please don't overwhelm the server with requests.")
		api.webSocket("live") { req, ws in
			req.application.webSocketManagerSpots?.track(ws)
		}.description("Websocket that broadcasts any new Spots and Spot State-Updates.")

		let apiAuthed = api.grouped(authMiddleware)
		let apiAuthedUser = apiAuthed.grouped("user")
		apiAuthedUser.get("current", use: apiCurrentUserSpot(req:)).description("Get spot of the current user. Returns HTTP code 204 if no current spot exists. User auth required.")
		apiAuthedUser.post("qrt", use: apiCurrentUserQrt(req:)).description("Mark all spots for the current user as QRT. User auth required.")

		let spots = routes.grouped("spot")
		spots.get(use: spots(req:))
		let spotsAuthed = spots.grouped(authMiddleware)
		spotsAuthed.post("me", "qrt", use: markQrt(req:))
	}

	func spots(req: Request) async throws -> View {
		struct SpotContext: Codable, CommonContentProviding {
			let spots: [Spot]
			let canMarkQRT: Bool
			let common: CommonContent
		}
		let spots = try await Spot.query(on: req.db).with(\.$reference).filter(\.$state, .equal, .active).sort(\.$modificationDate, .descending).all()
		let hasUserSpot: Bool
		if let user = req.auth.get(UserModel.self) {
			let userSpot = spots.first { spot in
				spot.$activator.id == user.id
			}
			hasUserSpot = userSpot != nil
		} else {
			hasUserSpot = false
		}
		let context = SpotContext(spots: spots,
								  canMarkQRT: hasUserSpot,
								  common:req.commonContent)
		return try await req.view.render("spots-table", context)
	}

	func markQrt(req: Request) async throws -> Response {
		_ = try await apiCurrentUserQrt(req: req)
		return req.redirect(to: "/spot", redirectType: .normal)
	}

	@discardableResult
	func createOrRenew(spot: Spot, req: Request) async throws -> Spot {
		if let date = spot.modificationDate, date.timeIntervalSinceNow > 0 || date.timeIntervalSinceNow < -60  {
			// Don't publish spots with mod date older than 60s or in the future, e.g when logging QSOs with manual time.
			throw Abort(.badRequest, reason: "Spot modification date is older than 60s or in the future.")
		}
		let activeSpotsForUser = try await Spot.query(on: req.db).filter(\.$activator.$id, .equal, spot.$activator.id).with(\.$reference).filter(\.$state, .equal, .active).all()
		var spotToReturn = spot
		for (index, activeSpot) in activeSpotsForUser.enumerated() {
			if index == 0 {
				activeSpot.$activatorTrainer.id = spot.$activatorTrainer.id
				activeSpot.$reference.id = spot.$reference.id
				activeSpot.stationCallSign = spot.stationCallSign
				activeSpot.operator = spot.operator
				activeSpot.freq = spot.freq
				activeSpot.mode = spot.mode
				activeSpot.state = spot.state
			} else {
				activeSpot.state = .qrt
			}
			try await activeSpot.save(on: req.db)
			spotToReturn = activeSpot
		}
		if activeSpotsForUser.isEmpty {
			try await spot.save(on: req.db)
		}

		try await spotToReturn.$reference.load(on: req.db)
		try await req.application.webSocketManagerSpots?.broadcast(spotToReturn)
		return spotToReturn
	}

	// MARK: - API

	func apiSpots(req: Request) async throws -> [Spot] {
		try await Spot.query(on: req.db).with(\.$reference).sort(\.$modificationDate, .descending).all()
	}

	func apiCurrentUserSpot(req: Request) async throws -> Spot {
		let authedUser = try req.auth.require(UserModel.self)
		let spot = try await Spot.query(on: req.db).filter(\.$activator.$id, .equal, authedUser.requireID()).with(\.$reference).sort(\.$modificationDate, .descending).first()
		if let spot {
			return spot
		} else {
			throw Abort(.noContent)
		}
	}

	func apiCurrentUserQrt(req:Request) async throws -> HTTPStatus {
		let authedUser = try req.auth.require(UserModel.self)
		let updateSpotIds = try await Spot.query(on: req.db)
			.filter(\.$activator.$id, .equal, authedUser.requireID())
			.filter(\.$state, .equal, .active)
			.all(\.$id)
		try await Spot.query(on: req.db).filter(\.$id ~~ updateSpotIds).set(\.$state, to: .qrt).update()
		let spots = try await Spot.query(on: req.db).filter(\.$id ~~ updateSpotIds).with(\.$reference).all()
		let websocketManager = req.application.webSocketManagerSpots
		for spot in spots {
			try await websocketManager?.broadcast(spot)
		}
		return .noContent
	}

}
