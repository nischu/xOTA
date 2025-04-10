import Vapor

struct AwardCheckerActivatedAll: AwardChecker {
	let awardKind: Award.AwardKind = "activated-all"

	func generateAwards(for user: UserModel, app: Application) async throws -> [Award] {
		let referencesIds = try await Reference.query(on: app.db).all(\.$id)

		guard try await AwardQueryHelper().activated(for: user, app: app, referenceIds: referencesIds) else {
			return []
		}
		return try await [addAward(for: user, app: app)]
	}

	func title(namingTheme: NamingTheme) -> String {
		return "Activated all \(namingTheme.referencePlural)"
	}

	func fileName(callsign: String, namingTheme: NamingTheme) -> String {
		"\(escapedCallsign(callsign))-activated-all-\(namingTheme.referencePlural.lowercased())"
	}
}
