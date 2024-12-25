import Fluent
import Vapor

struct AwardCheckerActivatedLevel: AwardChecker {
	init(level: Int) {
		self.level = level
		awardKind = "activated-level-\(level)"
	}

	let level: Int
	let awardKind: Award.AwardKind

	func generateAwards(for user: UserModel, app: Application) async throws -> [Award] {
		let referencesIds = try await Reference
			.query(on: app.db)
			.filter(\.$title =~ "T-\(level)")
			.all(\.$id)

		guard try await AwardQueryHelper().activated(for: user, app: app, referenceIds: referencesIds) else {
			return []
		}
		return try await [addAward(for: user, app: app)]
	}

	func title(namingTheme: NamingTheme) -> String {
		return "Activated Level \(level)"
	}

	func fileName(callsign: String, namingTheme: NamingTheme) -> String {
		"\(escapedCallsign(callsign))-activated-level-\(level)"
	}
}
