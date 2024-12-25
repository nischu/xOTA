import Vapor

// 38C3 specific award between references T-91 and T-92 which are both in the basement of CCH.
struct AwardCheckerBasementConnection: AwardChecker {
	let awardKind: Award.AwardKind = "basement-connection"

	func generateAwards(for user: UserModel, app: Application) async throws -> [Award] {
		if try await AwardQueryHelper().hasRef2Ref(for: user, app: app, refNameA: "T-91", refNameB: "T-92") {
			return try await [addAward(for: user, app: app)]
		} else {
			return []
		}
	}

	dynamic func title(namingTheme: NamingTheme) -> String {
		return "Basement Connection (T2T between T-91 and T-92)"
	}

	func fileName(callsign: String, namingTheme: NamingTheme) -> String {
		"\(escapedCallsign(callsign))-basement-connection"
	}
}
