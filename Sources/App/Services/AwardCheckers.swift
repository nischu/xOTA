import Vapor

protocol AwardChecker {
	var awardKind: Award.AwardKind { get }
	func generateAwards(for user: UserModel, mode: QSO.Mode?, app: Application) async throws -> [Award]
	func title(namingTheme: NamingTheme) -> String
	func fileName(callsign: String, namingTheme: NamingTheme) -> String
}

extension AwardChecker {
	func addAward(for user:UserModel, app: Application, endorsement: String? = nil) async throws -> Award {
		let namingTheme = app.namingTheme
		let award = try Award(userId: user.requireID(), kind: awardKind, name: self.title(namingTheme: namingTheme), endorsement: endorsement)
		var filename = fileName(callsign: user.callsign.callsign, namingTheme: namingTheme)
		if let endorsement {
			let allowed = CharacterSet.alphanumerics
			let endorsementAddition = endorsement.components(separatedBy: allowed.inverted).joined(separator: "_")
			if !endorsementAddition.isEmpty {
				filename.append("-")
				filename.append(endorsementAddition)
			}
		}
		award.filename = filename
		try await award.save(on: app.db)
		return award
	}

	func escapedCallsign(_ callsign: String) -> String {
		return callsign.replacingOccurrences(of: "/", with: "_")
	}

	func endorsement(for mode: QSO.Mode?) -> String? {
		guard let mode else { return nil }
		return "Mode: \(mode.rawValue)"
	}
}

struct AwardCheckerKey: StorageKey {
	typealias Value = [AwardChecker]
}

extension Application {

	var awardCheckers: [AwardChecker] {
		get {
			self.storage[AwardCheckerKey.self] ?? []
		}
		set {
			self.storage[AwardCheckerKey.self] = newValue
		}
	}
}
