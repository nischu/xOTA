import Foundation
import Fluent
import Vapor
import Queues

struct UpdateSpots: AsyncScheduledJob {

	func run(context: QueueContext) async throws {
		let db = context.application.db
		// Mark spots not modified within the past 5 minutes as qrt
		let updateSpotIds = try await Spot.query(on: db)
			.filter(\.$state, .equal, .active)
			.filter(\.$modificationDate, .lessThan, Date(timeIntervalSinceNow: -5*60))
			.all(\.$id)
		try await Spot.query(on: db).filter(\.$id ~~ updateSpotIds).set(\.$state, to: .qrt).update()
		let spots = try await Spot.query(on: db).filter(\.$id ~~ updateSpotIds).with(\.$reference).all()
		let websocketManager = context.application.webSocketManagerSpots
		for spot in spots {
			try await websocketManager?.broadcast(spot)
		}

		// Delete spots older than 1h
		try await Spot.query(on: db)
			.filter(\.$state, .equal, .qrt)
			.filter(\.$modificationDate, .lessThan, Date(timeIntervalSinceNow: -60*60))
			.delete()
	}

}
