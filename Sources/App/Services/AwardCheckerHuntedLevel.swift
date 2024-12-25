import Fluent
import Vapor

struct AwardCheckerHuntedLevel: AwardChecker {
	init(level: Int) {
		self.level = level
		awardKind = "hunted-level-\(level)"
	}

	let level: Int
	let awardKind: Award.AwardKind

	func generateAwards(for user: UserModel, app: Application) async throws -> [Award] {
		let referencesIds = try await Reference
			.query(on: app.db)
			.filter(\.$title =~ "T-\(level)")
			.all(\.$id)

		guard try await AwardQueryHelper().hunted(for: user, app: app, referenceIds: referencesIds) else {
			return []
		}
		return try await [addAward(for: user, app: app)]
	}

	func title(namingTheme: NamingTheme) -> String {
		return "Hunted Level \(level)"
	}

	func fileName(callsign: String, namingTheme: NamingTheme) -> String {
		"\(escapedCallsign(callsign))-hunted-level-\(level)"
	}
}
