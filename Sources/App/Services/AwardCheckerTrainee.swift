import Fluent
import Vapor

struct AwardCheckerTrainee: AwardChecker {
	let awardKind: Award.AwardKind = "trainee"

	func generateAwards(for user: UserModel, app: Application) async throws -> [Award] {
		let qsosCount = try await QSO.query(on: app.db)
			.filter(\.$activator.$id == user.requireID())
			.filter(\.$activatorTrainer.$id != nil)
			.limit(1)
			.count()
		if qsosCount > 0 {
			return try await [addAward(for: user, app: app)]
		} else {
			return []
		}
	}

	dynamic func title(namingTheme: NamingTheme) -> String {
		return "Trainee"
	}

	func fileName(callsign: String, namingTheme: NamingTheme) -> String {
		"\(escapedCallsign(callsign))-trainee"
	}
}
