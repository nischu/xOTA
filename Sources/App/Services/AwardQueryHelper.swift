import Fluent
import FluentKit
import FluentSQL
import Vapor

struct AwardQueryHelper {

	func hasRef2Ref(for user: UserModel, app: Application, refNameA: String, refNameB: String, mode: QSO.Mode?) async throws -> Bool {
		let userId = try user.requireID()
		let referenceIds = try await Reference.query(on: app.db).group(.or, { query in
			query
				.filter(\.$title, .equal, refNameA)
				.filter(\.$title, .equal ,refNameB)
		}).all(\.$id)

		guard referenceIds.count == 2 else {
			app.logger.warning("AwardQueryHelper only only found \(referenceIds.count) for reference names '\(refNameA)' and '\(refNameB)'.")
			return false
		}

		let qsosCount = try await QSO.query(on: app.db)
			.filter(\.$activator.$id, .equal, userId)
			.group(.or) { query in
				query
					.group { query in
						// Activated A hunt B
						query
							.filter(\.$reference.$id, .equal, referenceIds[0])
							.filter(\.$huntedReference.$id, .equal, referenceIds[1])
					}
					.group { query in
						// Activated B hunt A
						query
							.filter(\.$reference.$id, .equal, referenceIds[1])
							.filter(\.$huntedReference.$id, .equal, referenceIds[0])
					}
			}
			.filterModeIfNonNil(mode)
			.count()
		// Currently we only check if any activator QSO is logged connecting both references.
		// Ideally we'd match up two Ref2Ref QSOs and only issue the award if the other station confirmed the Ref2Ref.
		return qsosCount > 0
	}

	func hunted(for user: UserModel, app: Application, referenceIds: [Reference.IDValue], mode: QSO.Mode?) async throws -> Bool {
		let userId = try user.requireID()
		let qsoReferenceIds = try await QSO.query(on: app.db)
			.group(.or) { builder in
				builder
					.filter(\.$hunter.$id, .equal, userId)
					.filter(\.$contactedOperatorUser.$id, .equal, userId)
			}
			.filter(\.$reference.$id ~~ referenceIds)
			.filterModeIfNonNil(mode)
			.unique()
			.all(\.$reference.$id)
		return Set(referenceIds) == Set(qsoReferenceIds)
	}

	func activated(for user: UserModel, app: Application, referenceIds: [Reference.IDValue], mode: QSO.Mode? = nil) async throws -> Bool {
		let userId = try user.requireID()
		let qsoReferenceIds = try await QSO.query(on: app.db)
			.filter(\.$activator.$id, .equal, userId)
			.filter(\.$reference.$id ~~ referenceIds)
			.filterModeIfNonNil(mode)
			.unique()
			.all(\.$reference.$id)

		return Set(referenceIds) == Set(qsoReferenceIds)
	}



	func activatedBands(for user: UserModel, app: Application, referenceIds: [Reference.IDValue]?, mode: QSO.Mode? = nil) async throws -> [String] {

		guard let sql = app.db as? SQLDatabase else { return [] }

		let userId = try user.requireID().uuidString
		let optionalModeQuery: SQLQueryString = if let mode {
			"AND mode = \(literal: mode.rawValue)"
		} else {
			""
		}
		let optionalReferenceIdSubquery: SQLQueryString = if let referenceIds, !referenceIds.isEmpty {
			"AND reference_id IN (\(literals: referenceIds.map(\.uuidString), joinedBy: ","))"
		} else {
			""
		}

		let bands = try await sql.raw(
			"""
			SELECT
			\(QSO.bandCaseStatement(as: "band"))
			FROM qsos
			WHERE
			activator_id = \(literal: userId)
			\(optionalReferenceIdSubquery)
			\(optionalModeQuery)
			GROUP BY band
			ORDER BY freq
			;
			""")
			.all(decodingColumn: "band", as: String.self)
		return bands
	}

	func activatedBandsPerReference(for user: UserModel, app: Application, referenceIds: [Reference.IDValue], mode: QSO.Mode? = nil) async throws -> [String : [String]] {
		guard !referenceIds.isEmpty else { return [:] }
		guard let sql = app.db as? SQLDatabase else { return [:] }

		struct ReferenceAndBand: Codable {
			let reference: String
			let band: String
		}

		let userId = try user.requireID().uuidString
		let optionalModeQuery: SQLQueryString = if let mode {
			"AND mode = \(literal: mode.rawValue)"
		} else {
			""
		}
		let referencesAndBands = try await sql.raw(
			"""
			SELECT
			reference_id as 'reference',
			\(QSO.bandCaseStatement(as: "band"))
			FROM qsos
			WHERE
			activator_id = \(literal: userId)
			AND reference_id IN (\(literals: referenceIds.map(\.uuidString), joinedBy: ","))
			\(optionalModeQuery)
			GROUP BY band, reference
			ORDER BY freq
			;
			""")
			.all(decoding: ReferenceAndBand.self)
		var bandsPerReference: [String: [String]] = [:]
		for refAndBand in referencesAndBands {
			var bands = bandsPerReference[refAndBand.reference] ?? []
			bands.append(refAndBand.band)
			bandsPerReference[refAndBand.reference] = bands
		}
		return bandsPerReference
	}
}

extension QueryBuilder where Model == QSO {

	@discardableResult
	func filterModeIfNonNil(_ mode: QSO.Mode?) -> Self {
		if let mode {
			return self.filter(\.$mode, .equal, mode)
		} else {
			return self
		}
	}
}
