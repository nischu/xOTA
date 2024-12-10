import Fluent
import Vapor
import Queues
import QueuesFluentDriver

struct AwardCheckSchedulerInfo: Codable {
	let checkSinceDate: Date
	let identifier: String
}

struct AwardCheckScheduler: AsyncJob {
	typealias Payload = AwardCheckSchedulerInfo

	static let jobIdentifier1 = JobIdentifier(string: "scheduled-award-check-1")
	static let jobIdentifier2 = JobIdentifier(string: "scheduled-award-check-2")

	func dequeue(_ context: QueueContext, _ payload: AwardCheckSchedulerInfo) async throws {
		let db = context.application.db

		let nextCheckSinceDate = Date()
		let sinceDate = payload.checkSinceDate
		let qsos: [QSO] = try await QSO.query(on: db)
			.filter(\.$modificationDate, .greaterThanOrEqual, sinceDate)
			.field(\.$activator.$id)
			.field(\.$hunter.$id)
			.field(\.$contactedOperatorUser.$id)
			.all()
		var userIds: Set<UserModel.IDValue> = []
		for qso in qsos {
			userIds.insert(qso.$activator.id)
			if let id = qso.$hunter.id {
				userIds.insert(id)
			}
			if let id = qso.$contactedOperatorUser.id {
				userIds.insert(id)
			}
		}
		let queue = context.application.queues.queue
		for userId in userIds {
			try await queue.dispatch(CheckAwardElegibilityUser.self, .init(userId: userId))
		}

		// Alternate between two identifiers
		let nextIdentifier = payload.identifier == AwardCheckScheduler.jobIdentifier1.string ? AwardCheckScheduler.jobIdentifier2 : AwardCheckScheduler.jobIdentifier1
		let scheduleDate = Date(timeIntervalSinceNow: 5*60) // +5min
		try await queue.dispatch(AwardCheckScheduler.self, .init(checkSinceDate: nextCheckSinceDate, identifier: nextIdentifier.string), delayUntil: scheduleDate, id: nextIdentifier)
	}

	func error(_ context: QueueContext, _ error: any Error, _ payload: AwardCheckSchedulerInfo) async throws {
		context.logger.error("Failed to schedule award checks \(error)")
	}
}

struct AwardCheckSchedulerLifecycle: LifecycleHandler {
	func didBootAsync(_ application: Application) async throws {
		guard application.environment.arguments.contains("serve") else {
			return
		}
		// Check if a award schedule job is already queue, if not queue one for all QSOs.
		do {
			_ = try await application.queues.queue.get(AwardCheckScheduler.jobIdentifier1).get()
		} catch {
			do {
				_ = try await application.queues.queue.get(AwardCheckScheduler.jobIdentifier2).get()
			} catch {
				let sinceDate = Date.distantPast
				try await application.queues.queue.dispatch(AwardCheckScheduler.self, .init(checkSinceDate: sinceDate, identifier: AwardCheckScheduler.jobIdentifier1.string), id: AwardCheckScheduler.jobIdentifier1)
			}
		}
	}
}
