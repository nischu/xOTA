import Fluent
import Vapor

struct AwardCheckerTrainee: AwardChecker {
	let awardKind: Award.AwardKind = "trainee"
	let hasModeSpecificEndorsements: Bool = true

	func generateAwards(for user: UserModel, mode: QSO.Mode?, app: Application) async throws -> [Award] {
		let qsosCount = try await QSO.query(on: app.db)
			.filter(\.$activator.$id == user.requireID())
			.filter(\.$activatorTrainer.$id != nil)
			.filterModeIfNonNil(mode)
			.limit(1)
			.count()
		if qsosCount > 0 {
			return try await [addAward(for: user, app: app, endorsement: endorsement(for: mode))]
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
