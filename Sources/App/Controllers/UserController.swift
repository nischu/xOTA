import Fluent
import FluentKit
import FluentSQL
import Vapor

struct UserController: RouteCollection {
	let authMiddleware: [Middleware]

	func boot(routes: RoutesBuilder) throws {
		let userAPI = routes.grouped("api","user")
		userAPI.get(use: index)
		/*
		user.post(use: create)
		user.group(":userID") { user in
			user.delete(use: delete)
		}
		 */

		let user = routes.grouped("user")
		user.get { req async throws -> View in
			let users = try await index(req: req)

			struct UserContent: Content, CommonContentProviding {
				let userlist: [UserModel]
				let common: CommonContent
			}
			return try await req.view.render("users", UserContent(userlist: users, common: req.commonContent))
		}

		user.get(":callsign", use: specificUser)

		let authed = routes.grouped(authMiddleware)
		authed.get("profile", use: profile)
		authed.post("profile", "delete", use: deleteProfile)
		authed.get("profile", "adif", use: adif)
	}


	func profile(req: Request) async throws -> View {
		guard let user = req.auth.get(UserModel.self) else {
			throw Abort(.unauthorized)
		}

		struct UserContent: Content, CommonContentProviding {
			let user: UserModel
			let qsos: [QSO]
			let common: CommonContent
		}

		let qso = try await user.$activatorQsos.query(on: req.db).all()
		return try await req.view.render("profile", UserContent(user: user, qsos: qso, common: req.commonContent))
	}

	func specificUser(req: Request) async throws -> View {
		guard let callsign = req.parameters.get("callsign"),
			  let reference = try await UserModel.query(on: req.db)
			.filter(\.$callsign, .equal, callsign)
			.first()
			.get() else {
			throw Abort(.notFound)
		}

		struct UserQSOReferenceRankEntry: Codable {
			var title: String
			var mode: QSO.Mode
			var count: Int
		}
		let activated: [UserQSOReferenceRankEntry]
		let hunted: [UserQSOReferenceRankEntry]

		if let sql = req.db as? SQLDatabase {
			// The underlying database driver is SQL.
			let limit = 20
			activated = try await sql.raw("SELECT 'references'.title AS title, 'qsos'.mode AS mode, COUNT(*) AS count FROM 'qsos' INNER JOIN 'references' on 'references'.id = 'qsos'.reference_id WHERE 'qsos'.activator_id = '\(raw: try reference.requireID().uuidString)' GROUP BY 'qsos'.reference_id, 'qsos'.mode ORDER BY count DESC, title, mode LIMIT \(literal: limit);").all(decoding: UserQSOReferenceRankEntry.self)
			hunted = try await sql.raw("SELECT 'references'.title AS title, 'qsos'.mode AS mode, COUNT(*) AS count FROM 'qsos' INNER JOIN 'references' on 'references'.id = 'qsos'.reference_id WHERE 'qsos'.hunter_id = '\(raw: try reference.requireID().uuidString)' GROUP BY 'qsos'.reference_id, 'qsos'.mode ORDER BY count DESC, title, mode LIMIT \(literal: limit);").all(decoding: UserQSOReferenceRankEntry.self)
		} else {
			activated = []
			hunted = []
		}

		struct UserContent: Content, CommonContentProviding {
			let user: UserModel
			let activated: [UserQSOReferenceRankEntry]
			let hunted: [UserQSOReferenceRankEntry]
			let common: CommonContent
		}

		return try await req.view.render("user", UserContent(user: reference, activated: activated, hunted: hunted, common: req.commonContent))
	}

	func deleteProfile(req: Request) async throws -> View {
		guard let user = req.auth.get(UserModel.self) else {
			throw Abort(.unauthorized)
		}
		let callsign = user.callsign
		try await req.db.transaction { database in
			for qso in try await user.$activatorQsos.query(on: database).field(\.$id).all() {
				try await qso.delete(force: true, on: database)
			}
			for role in try await user.$specialRoles.query(on: database).field(\.$id).all() {
				try await role.delete(force: true, on: database)
			}
			try await user.delete(force: true, on: database)
		}
		
		req.auth.logout(UserModel.self)
		req.session.destroy()
		return try await req.view.render("profileDelete", ["callsign" : callsign])
	}

	func adif(req: Request) async throws -> Response {
		guard let user = req.auth.get(UserModel.self) else {
			throw Abort(.unauthorized)
		}

		let sqlQuery: SQLQueryString
		let headerComment: String
		let fileNamePart: String
		let adifMode: String = try req.query.get(at: "adif-mode")
		switch adifMode {
		case "hunter":
			sqlQuery = "SELECT date, call AS 'stationCallsign', station_callsign AS 'call', freq, mode, rst_sent AS 'rstRcvt', rst_rcvd AS 'rstSent', a.title AS 'sigInfo', h.title AS 'mySigInfo' FROM qsos LEFT JOIN 'references' AS a ON qsos.reference_id = a.id LEFT JOIN 'references' AS h ON qsos.hunted_reference_id = h.id WHERE qsos.hunter_id = '\(raw: try user.requireID().uuidString)';"
			headerComment =  "Hunter QSOs for \(user.callsign) based on activator logs."
			fileNamePart = "hunted"
		case "hunter-no-r2r":
			sqlQuery = "SELECT date, call AS 'stationCallsign', station_callsign AS 'call', freq, mode, rst_sent AS 'rstRcvt', rst_rcvd AS 'rstSent', a.title AS 'sigInfo' FROM qsos LEFT JOIN 'references' AS a ON qsos.reference_id = a.id WHERE qsos.hunter_id = '\(raw: try user.requireID().uuidString)' AND qsos.hunted_reference_id IS NULL;"
			headerComment =  "Hunter QSOs for \(user.callsign) based on activator logs excluding \(req.commonContent.namingTheme.referenceSingular)2\(req.commonContent.namingTheme.referenceSingular)."
			fileNamePart = "hunted-no-r2r"
		case "activator":
			fallthrough
		default:
			sqlQuery = "SELECT date, call, station_callsign AS 'stationCallsign', freq, mode, rst_sent AS 'rstSent', rst_rcvd AS 'rstRcvt', a.title AS 'mySigInfo', h.title AS 'sigInfo' FROM qsos LEFT JOIN 'references' AS a ON qsos.reference_id = a.id LEFT JOIN 'references' AS h ON qsos.hunted_reference_id = h.id WHERE qsos.activator_id = '\(raw: try user.requireID().uuidString)';"
			headerComment =  "Activator QSOs for \(user.callsign)."
			fileNamePart = "activated"
		}

		return try await adif(req: req, query:sqlQuery , headerComment:headerComment, filename: "\(user.callsign)_37C3_TOTA_\(fileNamePart).adif")
	}

	func adif(req: Request, query: SQLQueryString, headerComment: String, filename: String) async throws -> Response {
		guard req.auth.get(UserModel.self) != nil else {
			throw Abort(.unauthorized)
		}

		struct UserQSOReferenceRankEntry: Codable {
			var title: String
			var mode: QSO.Mode
			var count: Int
		}
		let qsos: [ADIFQSOEntry]
		struct ADIFQSOEntry: Codable, ADIFGeneratorQSO {
			var date: Date
			var call: String
			var stationCallsign: String
			var freq: Int
			var mode: String
			var rstSent: String?
			var rstRcvt: String?
			var sigInfo: String?
			var mySigInfo: String?

		}

		if let sql = req.db as? SQLDatabase {
			// The underlying database driver is SQL.
			qsos = try await sql.raw(query).all(decoding: ADIFQSOEntry.self)
		} else {
			qsos = []
		}
		let adifGenerator = ADIFGenerator(headerComment: headerComment, specialInterestGroup: "TOTA", qsos: qsos)

		var headers = HTTPHeaders()
		headers.contentDisposition = HTTPHeaders.ContentDisposition(.attachment, filename: filename)
		return Response(headers: headers, body: .init(string: String(describing: adifGenerator)))
	}


	// MARK: – API

	func index(req: Request) async throws -> [UserModel] {
		try await UserModel.query(on: req.db).all()
	}


	/*
	func create(req: Request) async throws -> UserModel {
		let user = try req.content.decode(UserModel.self)
		try await user.save(on: req.db)
		return user
	}
	
	func delete(req: Request) async throws -> HTTPStatus {
		guard let user = try await UserModel.find(req.parameters.get("userID"), on: req.db) else {
			throw Abort(.notFound)
		}
		try await user.delete(on: req.db)
		return .noContent
	}
	 */
}
