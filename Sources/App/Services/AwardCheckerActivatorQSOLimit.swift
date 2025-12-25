import Vapor

struct AwardCheckerActivatorQSOLimit: AwardChecker {
	let awardKind: Award.AwardKind
	let hasModeSpecificEndorsements: Bool = true
	let requiredQsoCount: Int
	let awardTitle: String

	init(awardKind: Award.AwardKind, requiredQsoCount: Int, awardTitle: String) {
		self.awardKind = awardKind
		self.requiredQsoCount = requiredQsoCount
		self.awardTitle = awardTitle
	}

	func generateAwards(for user: UserModel, mode: QSO.Mode?, app: Application) async throws -> [Award] {

		guard try await QSO.query(on: app.db)
			.filter(\.$activator.$id, .equal, user.requireID())
			.filterModeIfNonNil(mode)
			.count() >= requiredQsoCount else {
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
