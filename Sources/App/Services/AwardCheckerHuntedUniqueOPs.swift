import Vapor

struct AwardCheckerHuntedUniqueOPs: AwardChecker {
	init(uniqueOpsNeeded: Int, kind: String, title: String) {
		self.uniqueOpsNeeded = uniqueOpsNeeded
		awardKind = kind
		awardTitle = title
	}

	let uniqueOpsNeeded: Int
	let awardKind: Award.AwardKind
	let awardTitle: String
	let hasModeSpecificEndorsements: Bool = true

	func generateAwards(for user: UserModel, mode: QSO.Mode?, app: Application) async throws -> [Award] {
		let userId = try user.requireID()
		let distincedHuntedActivatorsCount = try await QSO.query(on: app.db)
			.group(.or) { builder in
				builder
					.filter(\.$hunter.$id, .equal, userId)
					.filter(\.$contactedOperatorUser.$id, .equal, userId)
			}
			.field(\.$activator.$id)
			.filterModeIfNonNil(mode)
			.count()

		guard distincedHuntedActivatorsCount >= uniqueOpsNeeded else {
			return []
		}
		return try await [addAward(for: user, app: app, endorsement: endorsement(for: mode))]
	}

	func title(namingTheme: NamingTheme) -> String {
		return awardTitle
	}

	func fileName(callsign: String, namingTheme: NamingTheme) -> String {
		"\(escapedCallsign(callsign))-\(awardKind)"
	}
}
