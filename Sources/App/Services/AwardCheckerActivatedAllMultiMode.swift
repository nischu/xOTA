import Vapor

struct AwardCheckerActivatedAllMultiMode: AwardChecker {
	let modeCount: Int
	let awardKind: Award.AwardKind
	let hasModeSpecificEndorsements: Bool = false
	let awardTitle: String

	init(modeCount: Int, title: String) {
		self.modeCount = modeCount
		awardKind = "activated-all-multi-mode-\(modeCount)"
		awardTitle = title
	}

	func generateAwards(for user: UserModel, mode: QSO.Mode?, app: Vapor.Application) async throws -> [Award] {
		let userId = try user.requireID()
		let awards = try await Award
			.query(on: app.db)
			.filter(\.$kind, .equal, AwardCheckerActivatedAll.awardKind)
			.filter(\.$user.$id, .equal, userId)
			.filter(\.$endorsement, .notEqual, nil)
			.all()
		if awards.count >= modeCount {
			let modes = awards.map(\.endorsement).compactMap {
				// This makes assumptions about the endorsement format.
				return $0?.replacing("Mode: ", with: "")
			}.sorted()

			let endorsement = "Modes: \(modes.joined(separator: ", "))"
			return try await [addAward(for: user, app: app, endorsement: endorsement)]
		} else {
			return []
		}
	}

	func title(namingTheme: NamingTheme) -> String {
		awardTitle
	}

	func fileName(callsign: String, namingTheme: NamingTheme) -> String {
		"\(callsign)-\(awardKind)"
	}

}
