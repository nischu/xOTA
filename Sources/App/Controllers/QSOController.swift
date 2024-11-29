import FluentKit
import Vapor


struct QSOController: RouteCollection {
	let authMiddleware: [Middleware]
	let namingTheme: NamingTheme

	func boot(routes: RoutesBuilder) throws {
		let api = routes.grouped("api", "qso")

		let apiAuthed = api.grouped(authMiddleware)
		apiAuthed.get("me", use: apiQsosUser(req:)).description("Get qsos of the current user. User auth required.")
		apiAuthed.group(":qsoId") { qso in
			qso.delete(use: delete).description("Delete a specific QSO. User auth required.")
		}

		api.get("", use: apiQsos(req:)).description("All qsos, no auth required. Please don't overwhelm the server with requests.")

		routes.get("qsos", use: qsosDashboard)

		let qsoForReference = routes.grouped(namingTheme.referenceSlugPathComponent, ":referenceId", "qso")
		qsoForReference.get(use:qsosForReference)

		let authed = routes.grouped(authMiddleware)
		let log = authed.grouped(namingTheme.referenceSlugPathComponent, ":referenceId", "log")

		let isLoggingDisabled = CommonContent.loggingDisabled

		if isLoggingDisabled {
			log.get(use: loggingDisabled)
			log.post(use: loggingDisabled)
		} else {
			log.get(use:getLog)
			log.post(use: postLog)
		}

		let editQSO = authed.grouped("qso", "edit", ":qsoId")
		if isLoggingDisabled {
			editQSO.get(use: loggingDisabled)
			editQSO.post(use: loggingDisabled)
		} else {
			editQSO.get(use: getEditQSO)
			editQSO.post(use: postEditQSO)
		}
	}

	func qsosForReference(req: Request) async throws -> View {
		let reference = try await ReferenceController(namingTheme: namingTheme).specific(req: req)
		let referenceId = try reference.requireID()

		struct QSOsContext: Encodable, CommonContentProviding {
			let title: String
			let qsos: [QSO]
			let common: CommonContent
		}
		let qsos = try await QSO.query(on: req.db)
			.filter(\.$reference.$id == referenceId)
			.limit(100)
			.all()
		let context = QSOsContext(title: reference.title, qsos: qsos, common: req.commonContent)
		return try await req.view.render("qsos", context)
	}

	struct QSOContext : Codable, Validatable {
		enum DateTimeSource: String, RawRepresentable, Codable {
			case auto
			case manual
		}
		var reference: String
		var callsign: String?
		var huntedReference: String?
		var dateTimeSource: DateTimeSource = .auto
		var manualDate: String?
		var freq: Int = 430200
		var mode: QSO.Mode = .FM
		var rst_sent: String?
		var rst_rcvd: String?
		static func validations(_ validations: inout Validations) {
			validations.add("callsign", as: String.self, is:.callsign)
			let rstPattern = "[0-5][0-9][0-9]?"
			validations.add("rst_sent", as: String.self, is:.pattern(rstPattern), customFailureDescription: "is not a valid RST sent value.")
			validations.add("rst_rcvd", as: String.self, is:.pattern(rstPattern), customFailureDescription: "is not a valid RST received value.")
			validations.add("freq", as: Int.self, is: .range(3500...1300000), customFailureDescription: "not a valid frequency in kHz.")
		}

		mutating func resetForNextQSO() {
			callsign = nil
			huntedReference = nil
			dateTimeSource = .auto
			manualDate = nil
		}
	}
	struct LogQSOContext: Codable, CommonContentProviding {
		var editing: Bool
		var formTitle: String
		var user: UserModel
		var error: String?
		var formPath: String
		var qso: QSOContext?
		var modes: [QSO.Mode] = QSO.Mode.allCases
		var knownCallsigns: [String]
		var knownReferences: [String]
		let common: CommonContent
	}

	func getLog(req: Request) async throws -> View {
		let authedUser = try req.auth.require(UserModel.self)

		let reference = try await ReferenceController(namingTheme: namingTheme).specific(req:req)
		return try await req.view.render("logQSO", LogQSOContext(editing:false, formTitle:"Log QSO at \(reference.title)", user:authedUser, formPath:req.url.path, qso:QSOContext(reference: reference.title), knownCallsigns: knownCallsigns(req: req), knownReferences: knownReferences(req: req), common: req.commonContent))
	}

	func knownCallsigns(req: Request) async throws -> [String] {
		try await UserModel.query(on: req.db).field(\.$callsign).sort(\.$callsign).all().map(\.callsign)
	}

	func knownReferences(req: Request) async throws -> [String] {
		try await Reference.query(on: req.db).field(\.$title).sort(\.$title).all().map(\.title)
	}

	let isoDateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions.remove(.withTimeZone)
		return formatter
	}()


	func postLog(req: Request) async throws -> View {
		let reference = try await ReferenceController(namingTheme: namingTheme).specific(req: req)
		return try await createOrUpdateLog(req: req, title:"Log QSO at \(reference.title)") { qsoInfo in
			try await QSO(activator: qsoInfo.activator, hunter: qsoInfo.hunter, reference: qsoInfo.reference, huntedReference: qsoInfo.huntedReference, date: qsoInfo.date, call:qsoInfo.call, stationCallSign: qsoInfo.stationCallSign, freq: qsoInfo.freq, mode: qsoInfo.mode, rstSent: qsoInfo.rstSent, rstRcvt: qsoInfo.rstRcvt)
				.save(on: req.db)
		}
	}

	func getEditQSO(req: Request) async throws -> View {
		let authedUser = try req.auth.require(UserModel.self)
		guard let qsoUUID = req.parameters.get("qsoId", as: UUID.self),
			  let qso = try await QSO.find(qsoUUID, on: req.db) else {
			throw Abort(.notFound)
		}

		try await qso.$reference.load(on: req.db)
		try await qso.$huntedReference.load(on: req.db)
		let qsoContext = QSOContext(reference: qso.reference.title, callsign: qso.call, huntedReference: qso.huntedReference?.title, dateTimeSource: .manual, manualDate: isoDateFormatter.string(from: qso.date), freq: qso.freq, mode: qso.mode, rst_sent: qso.rstSent, rst_rcvd: qso.rstRcvt)
		return try await req.view.render("logQSO", LogQSOContext(editing:true, formTitle: "Edit QSO", user: authedUser, formPath: req.url.path, qso:qsoContext, knownCallsigns: knownCallsigns(req: req), knownReferences: knownReferences(req: req), common: req.commonContent))

	}

	func postEditQSO(req: Request) async throws -> View {
		let userModel = try req.auth.require(UserModel.self)

		guard let qsoUUID = req.parameters.get("qsoId", as: UUID.self),
			  let qso = try await QSO.find(qsoUUID, on: req.db) else {
			throw Abort(.notFound)
		}

		guard userModel.id == qso.$activator.id else {
			throw Abort(.forbidden)
		}

		return try await createOrUpdateLog(req: req, title:"Update QSO", editing: true) { qsoInfo in
			qso.$activator.id = try qsoInfo.activator.requireID()
			qso.$hunter.id = try qsoInfo.hunter?.requireID()
			qso.$reference.id = try qsoInfo.reference.requireID()
			qso.$huntedReference.id = try qsoInfo.huntedReference?.requireID()
			qso.date = qsoInfo.date
			qso.call = qsoInfo.call
			qso.stationCallSign = qsoInfo.stationCallSign
			qso.freq = qsoInfo.freq
			qso.mode = qsoInfo.mode
			qso.rstSent = qsoInfo.rstSent
			qso.rstRcvt = qsoInfo.rstRcvt

			try await qso.save(on: req.db)
		}

	}


	struct CreateUpdateQSOModel {

		var activator: UserModel
		var hunter: UserModel?
		var reference: Reference
		var huntedReference: Reference?
		var date: Date
		var call: String
		var stationCallSign: String
		var freq: Int
		var mode: QSO.Mode
		var rstSent: String
		var rstRcvt: String

		init(activator: UserModel, hunter: UserModel? = nil, reference: Reference, huntedReference: Reference? = nil, date: Date, call: String, stationCallSign: String, freq: Int, mode: QSO.Mode, rstSent: String, rstRcvt: String) {
			self.activator = activator
			self.hunter = hunter
			self.reference = reference
			self.huntedReference = huntedReference
			self.date = date
			self.call = call
			self.stationCallSign = stationCallSign
			self.freq = freq
			self.mode = mode
			self.rstSent = rstSent
			self.rstRcvt = rstRcvt
		}

		init(qso: QSO) {
			self.activator = qso.activator
			self.hunter = qso.hunter
			self.reference = qso.reference
			self.huntedReference = qso.huntedReference
			self.date = qso.date
			self.call = qso.call
			self.stationCallSign = qso.stationCallSign
			self.freq = qso.freq
			self.mode = qso.mode
			self.rstSent = qso.rstSent ?? ""
			self.rstRcvt = qso.rstRcvt ?? ""
		}
	}

	func createOrUpdateLog(req: Request, title:String, editing: Bool = false, save: (CreateUpdateQSOModel) async throws -> ()) async throws -> View {

		let authedUser = try req.auth.require(UserModel.self)

		let form = try req.content.decode(QSOContext.self)

		let reference = try await Reference.query(on: req.db)
			.filter(\.$title, .equal, form.reference)
			.first()
			.get()

		var errorMessage: String? = nil

		if reference == nil {
			errorMessage = "Reference not found."
		}

		if errorMessage == nil {
			do {
				try QSOContext.validate(content: req)
			} catch let validationError as ValidationsError {
				errorMessage = validationError.description
			} catch {
				errorMessage = "Unknown error"
			}
			if errorMessage == nil, authedUser.callsign == form.callsign {
				errorMessage = "You can't log a QSO with yourself"
			}
		}

		let date: Date?
		if errorMessage == nil {
			switch (form.dateTimeSource) {
			case .auto:
				date = Date()
			case .manual:
				if let manualDate = form.manualDate {
					let decodedDate = isoDateFormatter.date(from: manualDate)
					if decodedDate != nil {
						date = decodedDate
					} else {
						// Try appending :00 for seconds.
						date = isoDateFormatter.date(from: manualDate+":00")
					}
				} else {
					date = nil
				}
			}
			if date == nil || date! > Date() {
				errorMessage = "Date/time needs to be 'auto' or a valid date/time in the past in UTC."
			}
		} else {
			date = nil
		}
		let huntedReference: Reference?
		if errorMessage == nil, let huntedRefTitle = form.huntedReference, !huntedRefTitle.isEmpty {
			huntedReference = try await Reference.query(on: req.db)
				.filter(\.$title, .equal, huntedRefTitle.uppercased())
				.field(\.$id)
				.first()
				.get()
			if huntedReference == nil {
				errorMessage = "\(namingTheme.referenceSingular) \(huntedRefTitle) not found."
			}
		} else {
			huntedReference = nil
		}

		var nextForm = form
		if errorMessage == nil {
			var hunter: UserModel? = nil
			if let hunterCall = form.callsign {
				hunter = try await UserModel.query(on: req.db)
					.filter(\.$callsign, .equal, normalizedCallsign(hunterCall))
					.field(\.$id)
					.first()
					.get()
			}
			if let hunterCall = form.callsign, let rstSent = form.rst_sent, let rstRcvd = form.rst_rcvd, let date {
				try await save(CreateUpdateQSOModel(activator: authedUser, hunter: hunter, reference: reference!, huntedReference: huntedReference, date: date, call: normalizedCallsign(hunterCall), stationCallSign: normalizedCallsign(authedUser.callsign), freq: form.freq, mode: form.mode, rstSent: rstSent, rstRcvt: rstRcvd))
				if !editing {
					nextForm.resetForNextQSO()
				}
				errorMessage = "Successfully saved your QSO with \(hunterCall)."
			}
		}

		return try await req.view.render("logQSO", LogQSOContext(editing:editing, formTitle:title, user:authedUser, error:errorMessage, formPath:req.url.path, qso:nextForm, knownCallsigns: knownCallsigns(req: req), knownReferences: knownReferences(req: req), common: req.commonContent))
	}

	func loggingDisabled(req: Request) async throws -> Response {
		return req.redirect(to: "/rules")
	}

	func qsosDashboard(req: Request) async throws -> View {
		let queryCount = try? req.query.get(Int.self, at: "count")
		let count = min(queryCount ?? 25, 100)
		let autorefresh = (try? req.query.get(Bool.self, at: "refresh")) ?? false
		var queryInterval = try? req.query.get(Int.self, at: "interval")
		if let interval = queryInterval {
			queryInterval = max(interval, 5)
		}
		struct QSOsContext: Encodable, CommonContentProviding {
			let autorefresh: Bool
			let interval: Int?
			let count: Int?
			let qsos: [QSO]
			let formPath: String
			let common: CommonContent
		}
		let qsos = try await QSO.query(on: req.db)
			.sort(\.$date, .descending)
			.limit(count)
			.with(\.$reference)
			.with(\.$huntedReference)
			.all()
		let context = QSOsContext(autorefresh: autorefresh, interval:queryInterval, count: queryCount, qsos: qsos, formPath: req.url.path, common: req.commonContent)
		return try await req.view.render("recentQsos", context)
	}

	// MARK: – API


	func delete(req: Request) async throws -> HTTPStatus {
		guard let qso = try await QSO.find(req.parameters.get("qsoId"), on: req.db) else {
			throw Abort(.notFound)
		}
		let authedUser = try req.auth.require(UserModel.self)
		guard qso.activator.id == authedUser.id else {
			throw Abort(.forbidden)
		}
		try await qso.delete(on: req.db)
		return .noContent
	}

	func apiQsos(req: Request, queryBuilder: QueryBuilder<QSO>) async throws -> Page<some Content> {

		struct QSOContent: Content {
			var id: UUID?
			var reference: String
			var hunted_reference: String?
			var date: Date
			var call: String
			var station_callsign: String
			var freq: Int
			var mode: QSO.Mode
			var rstSent: String?
			var rstRcvt: String?

			init(with qso:QSO) {
				self.id = qso.id
				self.reference = qso.reference.title
				self.hunted_reference = qso.huntedReference?.title
				self.date = qso.date
				self.call = qso.call
				self.station_callsign = qso.stationCallSign
				self.freq = qso.freq
				self.mode = qso.mode
				self.rstSent = qso.rstSent
				self.rstRcvt = qso.rstRcvt
			}
		}

		return try await queryBuilder
			.field(\.$id)
			.field(\.$date)
			.field(\.$stationCallSign)
			.field(\.$call)
			.field(\.$freq)
			.field(\.$mode)
			.field(\.$rstSent)
			.field(\.$rstRcvt)
			.field(.path([.string("hunted_reference_id")], schema: "qsos"))
			.with(\.$huntedReference)
			.field(.path([.string("reference_id")], schema: "qsos"))
			.with(\.$reference)
			.sort(\.$date, .descending)
			.paginate(for: req).map { QSOContent(with: $0) }
	}

	func apiQsos(req: Request) async throws -> Page<some Content> {
		try await apiQsos(req: req, queryBuilder: QSO.query(on: req.db))
	}

	func apiQsosUser(req: Request) async throws -> Page<some Content> {
		let authedUser = try req.auth.require(UserModel.self)
		return try await apiQsos(req: req, queryBuilder: authedUser.$activatorQsos.query(on: req.db))
	}

}
