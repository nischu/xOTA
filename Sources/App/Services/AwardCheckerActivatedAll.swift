import Vapor

struct AwardCheckerActivatedAll: AwardChecker {
	let awardKind: Award.AwardKind = "activated"

	func generateAwards(for user: UserModel, app: Application) async throws -> [Award] {
		let userId = try user.requireID()
		let referencesIds = try await Reference.query(on: app.db).all(\.$id)
		let qsoReferenceIds = try await QSO.query(on: app.db).filter(\.$activator.$id, .equal, userId).unique().all(\.$reference.$id)

		guard Set(referencesIds) == Set(qsoReferenceIds) else {
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
