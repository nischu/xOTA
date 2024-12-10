import Vapor

protocol AwardChecker {
	var awardKind: Award.AwardKind { get }
	func generateAwards(for user: UserModel, app: Application) async throws -> [Award]
	func title(namingTheme: NamingTheme) -> String
	func fileName(callsign: String, namingTheme: NamingTheme) -> String
}

extension AwardChecker {
	func addAward(for user:UserModel, app: Application) async throws -> Award {
		let namingTheme = app.namingTheme
		let award = try Award(userId: user.requireID(), kind: awardKind, name: self.title(namingTheme: namingTheme))
		award.filename = fileName(callsign: user.callsign.callsign, namingTheme: namingTheme)
		try await award.save(on: app.db)
		return award
	}

	func escapedCallsign(_ callsign: String) -> String {
		return callsign.replacingOccurrences(of: "/", with: "_")
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
