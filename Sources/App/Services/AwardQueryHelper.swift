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
			\(bandCaseStatement(as: "band"))
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
			\(bandCaseStatement(as: "band"))
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

	struct BandDefinition: Codable {
		let low: Int
		let high: Int?
		let name: String

		func sqliteCaseWhenStatement(column: SQLQueryString) -> SQLQueryString {
			if let high {
				"WHEN \(column) BETWEEN \(literal: low) AND \(literal: high) THEN \(literal: name)"
			} else {
				"WHEN \(column) >= \(literal: low) THEN \(literal: name)"
			}
		}
	}

	static func bandDefinitions() -> [BandDefinition] {
		[
			.init(low: 135, high: 138, name: "2.2 km"),
			.init(low: 472, high: 479, name: "630 m"),
			.init(low: 1810, high: 2000, name: "160 m"),
			.init(low: 5351, high: 5367, name: "60 m"),
			.init(low: 7000, high: 7200, name: "40 m"),
			.init(low: 10100, high: 10150, name: "30 m"),
			.init(low: 14000, high: 14350, name: "20 m"),
			.init(low: 18068, high: 18168, name: "17 m"),
			.init(low: 21000, high: 21450, name: "15 m"),
			.init(low: 24890, high: 24990, name: "12 m"),
			.init(low: 28000, high: 29700, name: "10 m"),
			.init(low: 50000, high: 52000, name: "6 m"),
			.init(low: 70150, high: 70210, name: "4 m"),
			.init(low: 144000, high: 146000, name: "2 m"),
			.init(low: 430000, high: 440000, name: "70 cm"),
			.init(low: 1240000, high: 1300000, name: "23 cm"),
			.init(low: 2320000, high: 2450000, name: "13 cm"),
			.init(low: 3400000, high: 3475000, name: "9 cm"),
			.init(low: 5650000, high: 5850000, name: "6 cm"),
			.init(low: 10000000, high: 10500000, name: "3 cm"),
			.init(low: 24000000, high: 24250000, name: "1.2 cm"),
			.init(low: 47000000, high: nil, name: "sub cm"),

			.init(low: 26565, high: 27405, name: "CB"),
			.init(low: 149025, high: 149113, name: "Freenet"),
			.init(low: 446006, high: 446193, name: "PMR"),
		]
	}

	private func bandCaseStatement(as rowName: SQLQueryString) -> SQLQueryString {
		"""
		CASE
			\(Self.bandDefinitions().map { $0.sqliteCaseWhenStatement(column: "freq")}.joined(separator: "\n"))
			ELSE 'N/A'
		END AS \(rowName)
		"""
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
