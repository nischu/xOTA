import Vapor
import Fluent
import FluentKit
import FluentSQL

/// Issue an award if an activator has >= \(requiredQsoCount) QSOs from the same reference
/// This award is issued per reference.
struct AwardCheckerActivatorSameRefQSOLimit: AwardChecker {
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

		struct UserReferenceQSOCounts: Codable {
			var title: String
			var count: Int
		}

		let referenceQSOCounts: [UserReferenceQSOCounts]
		if let sql = app.db as? SQLDatabase {
			// The underlying database driver is SQL.
			let userId = try user.requireID().uuidString
			let modeQuery: SQLQueryString = if let mode {
				"AND 'qsos'.mode = \(literal: mode.rawValue)"
			} else {
				""
			}
			referenceQSOCounts = try await sql.raw("SELECT 'references'.title AS title, COUNT(*) AS count FROM 'qsos' INNER JOIN 'references' on 'references'.id = 'qsos'.reference_id WHERE 'qsos'.activator_id = \(literal: userId) \(modeQuery) GROUP BY 'qsos'.reference_id HAVING count >= \(literal: requiredQsoCount) ORDER BY title ASC, title;").all(decoding: UserReferenceQSOCounts.self)
		} else {
			referenceQSOCounts = []
		}

		if referenceQSOCounts.isEmpty {
			return []
		} else {
			let existingAwardEndorsements = Set(try await Award.query(on: app.db)
				.filter(\.$kind, .equal, awardKind)
				.filter(\.$user.$id, .equal, user.requireID())
				.all(\.$endorsement))
			let endorsementsToIssue = referenceQSOCounts.map { reference in
				String([reference.title, endorsement(for: mode)].compactMap(\.self).joined(by: " "))
			}
				.filter { !existingAwardEndorsements.contains($0) }

			var awardsIssued: [Award] = []
			for endorsement in endorsementsToIssue {
				let award = try await addAward(for: user, app: app, endorsement: endorsement)
				awardsIssued.append(award)
			}
			return awardsIssued
		}
	}

	func title(namingTheme: NamingTheme) -> String {
		return awardTitle
	}

	func fileName(callsign: String, namingTheme: NamingTheme) -> String {
		"\(escapedCallsign(callsign))-\(awardKind)"
	}
}
