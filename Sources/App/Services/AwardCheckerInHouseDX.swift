import Vapor

// 39C3 Specific award: In-house DX-er T2T between T-41 and T-92 in CCH
struct AwardCheckerInHouseDX: AwardChecker {
	let awardKind: Award.AwardKind = "in-house-dx"

	func generateAwards(for user: UserModel, mode: QSO.Mode?, app: Application) async throws -> [Award] {
		if try await AwardQueryHelper().hasRef2Ref(for: user, app: app, refNameA: "T-41", refNameB: "T-92", mode: mode) {
			return try await [addAward(for: user, app: app, endorsement: endorsement(for: mode))]
		} else {
			return []
		}
	}

	dynamic func title(namingTheme: NamingTheme) -> String {
		return "In-house DX (T2T between T-41 and T-92)"
	}

	func fileName(callsign: String, namingTheme: NamingTheme) -> String {
		"\(escapedCallsign(callsign))-in-house-dx"
	}
}
