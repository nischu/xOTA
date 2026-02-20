import Vapor

struct AwardCheckerActivatedAllMultiBand: AwardChecker {
	let bandCount: Int
	let awardKind: Award.AwardKind
	let hasModeSpecificEndorsements: Bool = true
	let awardTitle: String

	init(bandCount: Int, title: String) {
		self.bandCount = bandCount
		awardKind = "activated-all-multi-band-\(bandCount)"
		awardTitle = title
	}

	func generateAwards(for user: UserModel, mode: QSO.Mode?, app: Vapor.Application) async throws -> [Award] {
		let referencesIds = try await Reference.query(on: app.db).all(\.$id)

		let refsAndBands = try await AwardQueryHelper().activatedBandsPerReference(for: user, app: app, referenceIds: referencesIds, mode: mode)
		// Check if all reference IDs were activated.
		guard refsAndBands.count == referencesIds.count else { return [] }

		let allBandsSorted = QSO.bandDefinitions().map(\.name)
		var activatedBands: Set<String> = Set(allBandsSorted)
		for (_, bands) in refsAndBands {
			activatedBands.formIntersection(bands)
		}
		// Check if enough bands were activated form all references
		guard activatedBands.count >= bandCount else { return [] }

		let activatedBandsSorted = allBandsSorted.filter { activatedBands.contains($0) }
		var endorsement = "Bands: \(activatedBandsSorted.joined(separator: ", "))"
		if let modeEndorsement = self.endorsement(for: mode) {
			endorsement.append(" \(modeEndorsement)")
		}
		return try await [addAward(for: user, app: app, endorsement: endorsement)]
	}

	func title(namingTheme: NamingTheme) -> String {
		awardTitle
	}

	func fileName(callsign: String, namingTheme: NamingTheme) -> String {
		"\(callsign)-\(awardKind)"
	}

}
