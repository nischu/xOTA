import Vapor

struct AwardCheckerActivatedAll: AwardChecker {
	static let awardKind: Award.AwardKind = "activated-all"
	let awardKind: Award.AwardKind = Self.awardKind

	let hasModeSpecificEndorsements: Bool = true

	func generateAwards(for user: UserModel, mode: QSO.Mode?, app: Application) async throws -> [Award] {
		let referencesIds = try await Reference.query(on: app.db).all(\.$id)

		guard try await AwardQueryHelper().activated(for: user, app: app, referenceIds: referencesIds, mode: mode) else {
			return []
		}
		return try await [addAward(for: user, app: app, endorsement: endorsement(for: mode))]
	}

	func title(namingTheme: NamingTheme) -> String {
		return "Activated all \(namingTheme.referencePlural)"
	}

	func fileName(callsign: String, namingTheme: NamingTheme) -> String {
		"\(escapedCallsign(callsign))-activated-all-\(namingTheme.referencePlural.lowercased())"
	}
}
