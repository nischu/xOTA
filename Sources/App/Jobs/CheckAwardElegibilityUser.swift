import Vapor
import Queues


struct CheckAwardElegibilityUserInfo: Codable {
	let userId: UserModel.IDValue
	let modes: [QSO.Mode]
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
			var existingAwards = try await Award.awardsQuery(for: userId, on: app.db).filter(\.$kind, .equal, checker.awardKind).all()
			context.logger.trace("CheckAwardElegibilityUser for userId \(userId), checker \(checker.awardKind) running.")
			var generatedAwards: [Award] = []
			if checker.hasModeSpecificEndorsements {
				for mode in payload.modes + [nil] {
					let potentialEndorsement = checker.endorsement(for: mode)
					// If a mode specific award was already issued, don't issue a mode agnostic awards or the same award again.
					guard existingAwards.first(where: { potentialEndorsement == nil || $0.endorsement == potentialEndorsement }) == nil else {
						context.logger.trace("CheckAwardElegibilityUser for userId \(userId) already has award \(checker.awardKind) with endorsement: \(potentialEndorsement ?? "<nil>").")
						continue
					}
					let awards = try await checker.generateAwards(for: user, mode: mode, app: app)
					generatedAwards.append(contentsOf: awards)
					existingAwards.append(contentsOf: awards)
					context.logger.trace("CheckAwardElegibilityUser for userId \(userId), mode:  \(mode?.rawValue ?? "<nil>") generated \(awards.count) awards.")
				}
			} else if existingAwards.isEmpty {
				// Generate mode unspecific awards
				let awards = try await checker.generateAwards(for: user, mode: nil, app: app)
				generatedAwards.append(contentsOf: awards)
			}
			for award in generatedAwards {
				try await app.queues.queue.dispatch(RenderAward.self, .init(awardId: award.requireID()))
			}
		}
	}

	func error(_ context: QueueContext, _ error: any Error, _ payload: Payload) async throws {
	}
}
