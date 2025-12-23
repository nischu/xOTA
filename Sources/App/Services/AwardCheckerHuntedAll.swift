import Vapor

struct AwardCheckerHuntedAll: AwardChecker {
	let awardKind: Award.AwardKind = "hunted-all"
	let hasModeSpecificEndorsements: Bool = true

	func generateAwards(for user: UserModel, mode: QSO.Mode?, app: Application) async throws -> [Award] {
		let userId = try user.requireID()
		let referencesIds = try await Reference.query(on: app.db).all(\.$id)
		let qsoReferenceIds = try await QSO.query(on: app.db)
			.group(.or) { builder in
				builder
					.filter(\.$hunter.$id, .equal, userId)
					.filter(\.$contactedOperatorUser.$id, .equal, userId)
			}
			.filterModeIfNonNil(mode)
		.unique()
		.all(\.$reference.$id)

		guard Set(referencesIds) == Set(qsoReferenceIds) else {
			return []
		}
		return try await [addAward(for: user, app: app, endorsement: endorsement(for: mode))]
	}

	dynamic func title(namingTheme: NamingTheme) -> String {
		return "Hunted all \(namingTheme.referencePlural)"
	}

	func fileName(callsign: String, namingTheme: NamingTheme) -> String {
		"\(escapedCallsign(callsign))-hunted-all-\(namingTheme.referencePlural.lowercased())"
	}
}
