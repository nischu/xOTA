import Vapor

// 38C3 Specific award: In-house DX-er T2T between T-41 and T-92 in CCH
struct AwardCheckerInHouseDX: AwardChecker {
	let awardKind: Award.AwardKind = "in-house-dx"

	func generateAwards(for user: UserModel, app: Application) async throws -> [Award] {
		if try await AwardQueryHelper().hasRef2Ref(for: user, app: app, refNameA: "T-41", refNameB: "T-92") {
			return try await [addAward(for: user, app: app)]
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
