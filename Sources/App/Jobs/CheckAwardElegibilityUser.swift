import Vapor
import Queues


struct CheckAwardElegibilityUserInfo: Codable {
	let userId: UserModel.IDValue
}

struct CheckAwardElegibilityUser: AsyncJob {
	typealias Payload = CheckAwardElegibilityUserInfo

	func dequeue(_ context: QueueContext, _ payload: Payload) async throws {
		let userId = payload.userId
		let app = context.application
		guard let user = try await UserModel.query(on: app.db).filter(\.$id, .equal, userId).with(\.$callsign).first() else {
			context.logger.error("Failed to find user with id \(userId) for award checks.")
			return
		}

		for checker in app.awardCheckers {
			if try await Award.awardsQuery(for: userId, on: app.db).filter(\.$kind, .equal, checker.awardKind).first() != nil {
				continue
			}
			let awards = try await checker.generateAwards(for: user, app: app)
			for award in awards {
				try await app.queues.queue.dispatch(RenderAward.self, .init(awardId: award.requireID()))
			}
		}
	}

	func error(_ context: QueueContext, _ error: any Error, _ payload: Payload) async throws {
	}
}
