import Fluent
import FluentKit
import FluentSQL
import Vapor

struct StatsController: RouteCollection {
	let namingTheme: NamingTheme

	func boot(routes: RoutesBuilder) throws {
		routes.get("stats", use: stats)
		routes.get("stats", "graph", use: graph)
	}

	func stats(req: Request) async throws -> View {
		struct StatsContent: Codable, CommonContentProviding {
			struct StatsTable: Codable {
				var columnNames: [String]
				var htmlRows: [String]
			}
			var references: StatsTable
			var ref2ref: StatsTable
			var activators: StatsTable
			var hunters: StatsTable
			var common: CommonContent
		}

		let modes = try await QSO.query(on: req.db).field(\.$mode).unique().sort(\.$mode).all(\.$mode).map(\.rawValue)

		let referenceRow: [any SQLRow]
		if let sql = req.db as? SQLDatabase {
			// The underlying database driver is SQL.

			let queryStart = "select ref.title AS title,"
			let queryModes = modes.reduce("") { previous, mode in
				previous + "count(case when qsos.mode = '\(mode)' then qsos.mode end) AS \(mode),"
			}
			let queryEnd = "count(*) AS sum FROM qsos RIGHT JOIN 'references' AS ref ON qsos.reference_id = ref.id GROUP BY qsos.reference_id ORDER BY ref.title;"

			referenceRow = try await sql.raw(SQLQueryString(queryStart + queryModes + queryEnd)).all()
		} else {
			referenceRow = []
		}
		
		let referencesHtmlRows = try referenceRow.map { sqlRow in
			let title = try sqlRow.decode(column: "title", as: String.self)
			return try modes.reduce("<td><a href=\"/\(namingTheme.referenceSlug)/\(title)/\">\(title)</a></td><td>\(sqlRow.decode(column: "sum", as: Int.self))</td>") { partialResult, mode in
				try partialResult + "<td>\(sqlRow.decode(column: mode, as: Int.self))</td>\n"
			}
		}

		let references = StatsContent.StatsTable(columnNames: ["Title", "All"] + modes, htmlRows: referencesHtmlRows)

		let referenceNames = try await Reference.query(on: req.db).field(\.$title).sort(\.$title).all(\.$title)

		let reference2ReferenceRow: [any SQLRow]
		if let sql = req.db as? SQLDatabase {

			let queryStart = "select ref.title AS title,"
			let queryReferences = referenceNames.reduce("") { previous, referenceName in
				previous + "count(case when hunted_ref.title = '\(referenceName)' then hunted_ref.title end) AS '\(referenceName)',"
			}
			let queryEnd = "count(*) AS sum FROM qsos RIGHT JOIN 'references' AS ref ON qsos.reference_id = ref.id RIGHT JOIN 'references' AS hunted_ref ON qsos.hunted_reference_id = hunted_ref.id WHERE ref.title != NULL GROUP BY qsos.reference_id ORDER BY ref.title;"

			reference2ReferenceRow = try await sql.raw(SQLQueryString(queryStart + queryReferences + queryEnd)).all()
		} else {
			reference2ReferenceRow = []
		}

		let references2referenceHtmlRows = try reference2ReferenceRow.map { sqlRow in
			let title = try sqlRow.decode(column: "title", as: String.self)
			return try referenceNames.reduce("<td><a href=\"/\(namingTheme.referenceSlug)/\(title)/\">\(title)</a></td>") { partialResult, ref in
				try partialResult + "<td>\(sqlRow.decode(column: ref, as: Int.self))</td>\n"
			}
		}

		let ref2ref = StatsContent.StatsTable(columnNames: ["Activated\\Hunted"] + referenceNames, htmlRows: references2referenceHtmlRows)

		func userRows(callsignColumn: String, userIDColumn: String) async throws -> [any SQLRow] {
			let userRows: [any SQLRow]
			if let sql = req.db as? SQLDatabase {
				// The underlying database driver is SQL.

				let queryStart = "select qsos.\(callsignColumn) AS 'call',"
				let queryReferences = referenceNames.reduce("") { previous, refTitle in
					previous + "count(case when ref.title = '\(refTitle)' then ref.title end) AS '\(refTitle)',"
				}
				let queryEnd = "count(*) AS sum FROM qsos LEFT JOIN 'references' AS ref ON qsos.reference_id = ref.id GROUP BY qsos.\(userIDColumn) ORDER BY sum DESC;"

				userRows = try await sql.raw(SQLQueryString(queryStart + queryReferences + queryEnd)).all()
			} else {
				userRows = []
			}
			return userRows
		}

		func userHtmlRow(for rows: [any SQLRow]) async throws -> [String] {
			return try rows.map { sqlRow in
				let call = try sqlRow.decode(column: "call", as: String.self)
				let percentEndcodedCall = call.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? ""
				return try referenceNames.reduce("<td><a href=\"/user/\(percentEndcodedCall)\">\(call)</a></td><td>\(sqlRow.decode(column: "sum", as: Int.self))</td>") { partialResult, reference in
					try partialResult + "<td>\(sqlRow.decode(column: reference, as: Int.self))</td>\n"
				}
			}
		}

		let activatorSQLRows = try await userRows(callsignColumn: "station_callsign", userIDColumn: "activator_id")
		let activatorsHtmlRows = try await userHtmlRow(for: activatorSQLRows)

		let hunterSQLRows = try await userRows(callsignColumn: "call", userIDColumn: "hunter_id")
		let hunterHtmlRows = try await userHtmlRow(for: hunterSQLRows)

		let activators = StatsContent.StatsTable(columnNames: ["Activator", "All"] + referenceNames, htmlRows: activatorsHtmlRows)
		let hunters = StatsContent.StatsTable(columnNames: ["Hunter", "All"] + referenceNames, htmlRows: hunterHtmlRows)
		let statsContent = StatsContent(references: references, ref2ref: ref2ref, activators:activators, hunters:hunters, common: req.commonContent)

		return try await req.view.render("stats", statsContent)
	}

	func graph(req: Request) async throws -> View {
		struct StatsContent: Codable, CommonContentProviding {
			struct QSO: Codable {
				var count: Int
				var date: String

				init(from decoder: Decoder) throws {
					let container: KeyedDecodingContainer<StatsContent.QSO.CodingKeys> = try decoder.container(keyedBy: StatsContent.QSO.CodingKeys.self)
					self.count = try container.decode(Int.self, forKey: StatsContent.QSO.CodingKeys.count)
					let date = try container.decode(Date.self, forKey: StatsContent.QSO.CodingKeys.date)
					self.date = ISO8601DateFormatter().string(from: date)
				}
			}
			var qsos: [QSO]
			var common: CommonContent
		}

		let qsos: [StatsContent.QSO]
		if let sql = req.db as? SQLDatabase {
			// The underlying database driver is SQL.
			qsos = try await sql.raw("SELECT row_number() OVER win AS count, date FROM qsos WINDOW win as (ORDER BY date);").all(decoding: StatsContent.QSO.self)
		} else {
			qsos = []
		}

		return try await req.view.render("graph", StatsContent(qsos: qsos, common: req.commonContent))
	}

}
