import Fluent
import Vapor

struct AwardCheckerTrainer: AwardChecker {
	let awardKind: Award.AwardKind = "trainer"

	func generateAwards(for user: UserModel, mode: QSO.Mode?, app: Application) async throws -> [Award] {
		if try await QSO.query(on: app.db)
			.filter(\.$activatorTrainer.$id == user.requireID())
			.filterModeIfNonNil(mode)
			.limit(1)
			.count() > 0 {
			return try await [addAward(for: user, app: app, endorsement: endorsement(for: mode))]
		} else {
			return []
		}
	}

	dynamic func title(namingTheme: NamingTheme) -> String {
		return "Trainer"
	}

	func fileName(callsign: String, namingTheme: NamingTheme) -> String {
		"\(escapedCallsign(callsign))-trainer"
	}
}
