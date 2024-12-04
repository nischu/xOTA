import Fluent
import FluentKit
import FluentSQL
import Vapor

struct UserController: RouteCollection {
	let authMiddleware: [Middleware]

	func boot(routes: RoutesBuilder) throws {
		/*
		let userAPI = routes.grouped("api","user")
		userAPI.get(use: index)
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
		let profile = authed.grouped("profile")
		profile.get(use: profile(req:))
		profile.post("delete", use: deleteProfile)
		profile.get("adif", use: adif)

		let callsignGroup = profile.grouped("callsign")
		let addCallsign = callsignGroup.grouped("add")
		addCallsign.get(use: addCallsign(req:))
		addCallsign.post(use: addCallsign(req:))
		callsignGroup.post(":callId", "delete", use: deleteCallsign(req:))
	}


	func profile(req: Request) async throws -> View {
		guard let user = req.auth.get(UserModel.self) else {
			throw Abort(.unauthorized)
		}

		struct UserContent: Content, CommonContentProviding {
			struct QSOGoup: Content {
				let title: String
				let qsos: [QSO]
				let editable: Bool
				let visible: Bool
			}
			let formPath: String
			let user: UserModel
			let qsoGroups: [QSOGoup]
			let hasTrainingQSOs: Bool
			let trainingCallsigns: [Callsign]
			let common: CommonContent
		}

		let userId = try user.requireID()
		let trainingCalls = try await user.$callsigns.query(on: req.db).filter(\.$kind == .training).all()
		let activatorQSOs = try await user.$activatorQsos.query(on: req.db).sort(\.$date, .descending).all()
		let hunterQSOs = try await QSO.query(on: req.db).group(.or, { $0.filter(\.$hunter.$id == userId).filter(\.$contactedOperatorUser.$id == userId) }).sort(\.$date, .descending).all()
		let trainingQSOs = try await QSO.query(on: req.db).filter(\.$activatorTrainer.$id == userId).sort(\.$date, .descending).all()
		let qsoGroups: [UserContent.QSOGoup] = [
			.init(title: "Activator QSOs", qsos: activatorQSOs, editable: true, visible: true),
			.init(title: "Hunter QSOs", qsos: hunterQSOs, editable: false, visible: true),
			.init(title: "Training QSOs", qsos: trainingQSOs, editable: true, visible: !trainingQSOs.isEmpty),
		]
		return try await req.view.render("profile", UserContent(formPath: req.url.path, user: user, qsoGroups: qsoGroups, hasTrainingQSOs:!trainingQSOs.isEmpty, trainingCallsigns: trainingCalls, common: req.commonContent))
	}

	func specificUser(req: Request) async throws -> View {
		guard let callsign = req.parameters.get("callsign"),
			  let user = try await UserModel.query(on: req.db)
			.join(Callsign.self, on: \UserModel.$id == \Callsign.$user.$id)
			.filter(Callsign.self, \.$callsign == callsign)
			.with(\.$callsign)
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
			let userId = try user.requireID().uuidString
			let limit = 20
			activated = try await sql.raw("SELECT 'references'.title AS title, 'qsos'.mode AS mode, COUNT(*) AS count FROM 'qsos' INNER JOIN 'references' on 'references'.id = 'qsos'.reference_id WHERE 'qsos'.activator_id = \(literal: userId) GROUP BY 'qsos'.reference_id, 'qsos'.mode ORDER BY count DESC, title, mode LIMIT \(literal: limit);").all(decoding: UserQSOReferenceRankEntry.self)
			hunted = try await sql.raw("SELECT 'references'.title AS title, 'qsos'.mode AS mode, COUNT(*) AS count FROM 'qsos' INNER JOIN 'references' on 'references'.id = 'qsos'.reference_id WHERE 'qsos'.hunter_id = \(literal: userId) OR 'qsos'.contacted_operator_user_id = \(literal: userId) GROUP BY 'qsos'.reference_id, 'qsos'.mode ORDER BY count DESC, title, mode LIMIT \(literal: limit);").all(decoding: UserQSOReferenceRankEntry.self)
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

		return try await req.view.render("user", UserContent(user: user, activated: activated, hunted: hunted, common: req.commonContent))
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
			let callsigns = try await user.$callsigns.query(on: database).field(\.$id).all()
			try await user.delete(force: true, on: database)
			for callsign in callsigns {
				try await callsign.delete(force:true, on: database)
			}
		}
		
		req.auth.logout(UserModel.self)
		req.session.destroy()
		return try await req.view.render("profileDelete", ["callsign" : callsign])
	}

	func addCallsign(req: Request) async throws -> Response {
		guard let user = req.auth.get(UserModel.self) else {
			throw Abort(.unauthorized)
		}
		
		struct CallsignForm: Content, Validatable {
			var trainingCallsign: String?
			static func validations(_ validations: inout Validations) {
				validations.add("trainingCallsign", as: String.self, is: .callsign)
			}
		}

		struct AddCallsignContext: Content, CommonContentProviding {
			var form: CallsignForm
			var formPath: String
			var error: String? = nil
			var common: CommonContent
		}

		if req.method == .GET {
			let form = CallsignForm()
			return try await req.view.render("profileCallsignAdd", AddCallsignContext(form: form, formPath: req.url.path, common: req.commonContent)).encodeResponse(for: req)
		}

		let form = try req.content.decode(CallsignForm.self)
		var errorMessage: String? = nil
		do {
			try CallsignForm.validate(content: req)
		} catch let validationError as ValidationsError {
			errorMessage = validationError.description
		} catch {
			errorMessage = "Unknown error"
		}

		if errorMessage == nil && user.callsign.kind != .licensed {
			errorMessage = "You need to be a licensed amateur to add a training callsign."
		}

		if errorMessage == nil {
			let count = try await user.$callsigns.get(on: req.db).count
			if count > 4 {
				errorMessage = "You already have \(count) callsigns associated to this account. Don't overdo it."
			}
		}

		let dedicatedTrainingCallsRegex = "(^(DN[0-8][A-Z]{1,4})$)"
		if errorMessage == nil {
			if let trainingCallString = normalizedCallsignOptional(form.trainingCallsign), !trainingCallString.isEmpty {
				let validTrainingCallSign: Bool
				if let range = trainingCallString.range(of: dedicatedTrainingCallsRegex, options: [.regularExpression]),
				   range.lowerBound == trainingCallString.startIndex && range.upperBound == trainingCallString.endIndex {
					validTrainingCallSign = true
				} else if trainingCallString.hasSuffix("/T") {
					validTrainingCallSign = true
				} else {
					validTrainingCallSign = false
				}

				if !validTrainingCallSign {
					errorMessage = "Callsign does not look like a valid German training callsign."
				}
				if try await Callsign.query(on: req.db).filter(\.$callsign == trainingCallString).field(\.$id).count() != 0 {
					errorMessage = "Training callsign \(trainingCallString) already exists."
				}
				if errorMessage == nil {
					let callsign = Callsign(callsign: trainingCallString, kind: .training)
					callsign.$user.id = try user.requireID()
					try await callsign.save(on: req.db)
				}
			} else {
				errorMessage = "Please enter a training callsign."
			}
		}

		if errorMessage != nil {
			return try await req.view.render("profileCallsignAdd", AddCallsignContext(form: form, formPath: req.url.path, error: errorMessage, common: req.commonContent)).encodeResponse(for: req)
		} else {
			return req.redirect(to: "/profile", redirectType: .normal)
		}
	}

	func deleteCallsign(req: Request) async throws -> Response {
		guard let user = req.auth.get(UserModel.self) else {
			throw Abort(.unauthorized)
		}

		guard let callIdString = req.parameters.get("callId"), let callId = UUID(callIdString) else {
			throw Abort(.badRequest)
		}
		guard let callsign = try await Callsign.find(callId, on: req.db) else {
			throw Abort(.notFound)
		}
		guard callsign.kind == .training else {
			// Only training calls can be deleted.
			throw Abort(.badRequest)
		}
		guard try callsign.$user.id == user.requireID() else {
			// Only callsigns of the signed-in user can be deleted.
			throw Abort(.unauthorized)
		}
		try await callsign.delete(on: req.db)
		return req.redirect(to: "/profile", redirectType: .normal)
	}

	func adif(req: Request) async throws -> Response {
		guard let user = req.auth.get(UserModel.self) else {
			throw Abort(.unauthorized)
		}

		let primaryCallsign = user.callsign.callsign

		let sqlQuery: SQLQueryString
		let headerComment: String
		let fileNamePart: String
		let adifMode: String = try req.query.get(at: "adif-mode")
		let userId = try user.requireID().uuidString
		switch adifMode {
		case "hunter":
			sqlQuery = "SELECT date, station_callsign AS 'call', operator AS contactedOperator, call AS 'stationCallsign', contacted_operator AS 'operator', freq, mode, rst_sent AS 'rstRcvt', rst_rcvd AS 'rstSent', a.title AS 'sigInfo', h.title AS 'mySigInfo' FROM qsos LEFT JOIN 'references' AS a ON qsos.reference_id = a.id LEFT JOIN 'references' AS h ON qsos.hunted_reference_id = h.id WHERE qsos.hunter_id = \(literal: userId) OR qsos.contacted_operator_user_id = \(literal: userId);"
			headerComment =  "Hunter QSOs for \(primaryCallsign) based on activator logs."
			fileNamePart = "hunted"
		case "hunter-no-r2r":
			sqlQuery = "SELECT date, station_callsign AS 'call', operator AS contactedOperator, call AS 'stationCallsign', contacted_operator AS 'operator', freq, mode, rst_sent AS 'rstRcvt', rst_rcvd AS 'rstSent', a.title AS 'sigInfo' FROM qsos LEFT JOIN 'references' AS a ON qsos.reference_id = a.id WHERE (qsos.hunter_id = \(literal: userId) OR qsos.contacted_operator_user_id = \(literal: userId)) AND qsos.hunted_reference_id IS NULL;"
			headerComment =  "Hunter QSOs for \(primaryCallsign) based on activator logs excluding \(req.commonContent.namingTheme.referenceSingular)2\(req.commonContent.namingTheme.referenceSingular)."
			fileNamePart = "hunted-no-r2r"
		case "trainer":
			sqlQuery = "SELECT date, call, contacted_operator AS 'contactedOperator', station_callsign AS 'stationCallsign', operator, freq, mode, rst_sent AS 'rstSent', rst_rcvd AS 'rstRcvt', a.title AS 'mySigInfo', h.title AS 'sigInfo' FROM qsos LEFT JOIN 'references' AS a ON qsos.reference_id = a.id LEFT JOIN 'references' AS h ON qsos.hunted_reference_id = h.id WHERE qsos.activator_trainer_id = \(literal: userId);"
			headerComment =  "Trainer QSOs for \(primaryCallsign)."
			fileNamePart = "trainer"
		case "activator":
			fallthrough
		default:
			sqlQuery = "SELECT date, call, contacted_operator AS 'contactedOperator', station_callsign AS 'stationCallsign', operator, freq, mode, rst_sent AS 'rstSent', rst_rcvd AS 'rstRcvt', a.title AS 'mySigInfo', h.title AS 'sigInfo' FROM qsos LEFT JOIN 'references' AS a ON qsos.reference_id = a.id LEFT JOIN 'references' AS h ON qsos.hunted_reference_id = h.id WHERE qsos.activator_id = \(literal: userId);"
			headerComment =  "Activator QSOs for \(primaryCallsign)."
			fileNamePart = "activated"
		}

		let activityNameForFile = req.application.namingTheme.activityName.replacingOccurrences(of: " ", with: "_")
		return try await adif(req: req, query:sqlQuery , headerComment:headerComment, filename: "\(primaryCallsign)_\(activityNameForFile)_\(fileNamePart).adif")
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
			var contactedOperator: String?
			var stationCallsign: String
			var `operator`: String?
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
		let namingTheme = req.application.namingTheme
		let adifGenerator = ADIFGenerator(headerComment: headerComment, programVersion: namingTheme.activityName, specialInterestGroup: namingTheme.adifSIG, qsos: qsos)

		var headers = HTTPHeaders()
		headers.contentDisposition = HTTPHeaders.ContentDisposition(.attachment, filename: filename)
		return Response(headers: headers, body: .init(string: String(describing: adifGenerator)))
	}


	// MARK: – API

	func index(req: Request) async throws -> [UserModel] {
		try await UserModel.query(on: req.db).with(\.$callsign).all()
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
