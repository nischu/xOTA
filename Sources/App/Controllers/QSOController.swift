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
			validations.add("callsign", as: String.self, is:.relaxedCallsign)
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
		var channelGroups: [RadioChannelGroup] = QSOController.licenseFreeChannels()
		let common: CommonContent
	}

	func getLog(req: Request) async throws -> View {
		let authedUser = try req.auth.require(UserModel.self)

		let reference = try await ReferenceController(namingTheme: namingTheme).specific(req:req)
		return try await req.view.render("logQSO", LogQSOContext(editing:false, formTitle:"Log QSO at \(reference.title)", user:authedUser, formPath:req.url.path, qso:QSOContext(reference: reference.title), knownCallsigns: knownCallsigns(req: req), knownReferences: knownReferences(req: req), common: req.commonContent))
	}

	func knownCallsigns(req: Request) async throws -> [String] {
		try await Callsign.query(on: req.db).field(\.$callsign).sort(\.$callsign).all().map(\.callsign)
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
			if errorMessage == nil, authedUser.callsign.callsign == form.callsign {
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
					.join(Callsign.self, on: \UserModel.$id == \Callsign.$user.$id)
					.filter(Callsign.self, \.$callsign == hunterCall)
					.field(\.$id)
					.first()
					.get()
			}
			if let hunterCall = form.callsign, let rstSent = form.rst_sent, let rstRcvd = form.rst_rcvd, let date {
				try await save(CreateUpdateQSOModel(activator: authedUser, hunter: hunter, reference: reference!, huntedReference: huntedReference, date: date, call: normalizedCallsign(hunterCall), stationCallSign: normalizedCallsign(authedUser.callsign.callsign), freq: form.freq, mode: form.mode, rstSent: rstSent, rstRcvt: rstRcvd))
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

	struct RadioChannelGroup: Codable {
		var name: String
		var channels: [RadioChannel]
		var licensedComment: String
	}

	struct RadioChannel: Codable {
		var name: String
		var frequency: Int // kHz
	}

	static func licenseFreeChannels() -> [RadioChannelGroup] {
		let pmr: [RadioChannel] = [
			.init(name: "PMR 1", frequency: 446_006),
			.init(name: "PMR 2", frequency: 446_018),
			.init(name: "PMR 3", frequency: 446_031),
			.init(name: "PMR 4", frequency: 446_043),
			.init(name: "PMR 5", frequency: 446_056),
			.init(name: "PMR 6", frequency: 446_068),
			.init(name: "PMR 7", frequency: 446_081),
			.init(name: "PMR 8", frequency: 446_093),
			.init(name: "PMR 9", frequency: 446_106),
			.init(name: "PMR 10", frequency: 446_118),
			.init(name: "PMR 11", frequency: 446_131),
			.init(name: "PMR 12", frequency: 446_143),
			.init(name: "PMR 13", frequency: 446_156),
			.init(name: "PMR 14", frequency: 446_168),
			.init(name: "PMR 15", frequency: 446_181),
			.init(name: "PMR 16", frequency: 446_193),
		]

		let freenet: [RadioChannel] = [
			.init(name:"Freenet 1", frequency: 149_0250),
			.init(name:"Freenet 2", frequency: 149_0375),
			.init(name:"Freenet 3", frequency: 149_0500),
			.init(name:"Freenet 4", frequency: 149_0875),
			.init(name:"Freenet 5", frequency: 149_1000),
			.init(name:"Freenet 6", frequency: 149_1125),
		]

		let cb: [RadioChannel] = [
			.init(name:"CB 1", frequency: 26_965),
			.init(name:"CB 2", frequency: 26_975),
			.init(name:"CB 3", frequency: 26_985),
			.init(name:"CB 4", frequency: 27_005),
			.init(name:"CB 5", frequency: 27_015),
			.init(name:"CB 6", frequency: 27_025),
			.init(name:"CB 7", frequency: 27_035),
			.init(name:"CB 8", frequency: 27_055),
			.init(name:"CB 9", frequency: 27_065),
			.init(name:"CB 10", frequency: 27_075),
			.init(name:"CB 11", frequency: 27_085),
			.init(name:"CB 12", frequency: 27_105),
			.init(name:"CB 13", frequency: 27_115),
			.init(name:"CB 14", frequency: 27_125),
			.init(name:"CB 15", frequency: 27_135),
			.init(name:"CB 16", frequency: 27_155),
			.init(name:"CB 17", frequency: 27_165),
			.init(name:"CB 18", frequency: 27_175),
			.init(name:"CB 19", frequency: 27_185),
			.init(name:"CB 20", frequency: 27_205),
			.init(name:"CB 21", frequency: 27_215),
			.init(name:"CB 22", frequency: 27_225),
			.init(name:"CB 23", frequency: 27_255),
			.init(name:"CB 24", frequency: 27_235),
			.init(name:"CB 25", frequency: 27_245),
			.init(name:"CB 26", frequency: 27_265),
			.init(name:"CB 27", frequency: 27_275),
			.init(name:"CB 28", frequency: 27_285),
			.init(name:"CB 29", frequency: 27_295),
			.init(name:"CB 30", frequency: 27_305),
			.init(name:"CB 31", frequency: 27_315),
			.init(name:"CB 32", frequency: 27_325),
			.init(name:"CB 33", frequency: 27_335),
			.init(name:"CB 34", frequency: 27_345),
			.init(name:"CB 35", frequency: 27_355),
			.init(name:"CB 36", frequency: 27_365),
			.init(name:"CB 37", frequency: 27_375),
			.init(name:"CB 38", frequency: 27_385),
			.init(name:"CB 39", frequency: 27_395),
			.init(name:"CB 40", frequency: 27_405),
			.init(name:"CB 41", frequency: 26_565),
			.init(name:"CB 42", frequency: 26_575),
			.init(name:"CB 43", frequency: 26_585),
			.init(name:"CB 44", frequency: 26_595),
			.init(name:"CB 45", frequency: 26_605),
			.init(name:"CB 46", frequency: 26_615),
			.init(name:"CB 47", frequency: 26_625),
			.init(name:"CB 48", frequency: 26_635),
			.init(name:"CB 49", frequency: 26_645),
			.init(name:"CB 50", frequency: 26_655),
			.init(name:"CB 51", frequency: 26_665),
			.init(name:"CB 52", frequency: 26_675),
			.init(name:"CB 53", frequency: 26_685),
			.init(name:"CB 54", frequency: 26_695),
			.init(name:"CB 55", frequency: 26_705),
			.init(name:"CB 56", frequency: 26_715),
			.init(name:"CB 57", frequency: 26_725),
			.init(name:"CB 58", frequency: 26_735),
			.init(name:"CB 59", frequency: 26_745),
			.init(name:"CB 60", frequency: 26_755),
			.init(name:"CB 61", frequency: 26_765),
			.init(name:"CB 62", frequency: 26_775),
			.init(name:"CB 63", frequency: 26_785),
			.init(name:"CB 64", frequency: 26_795),
			.init(name:"CB 65", frequency: 26_805),
			.init(name:"CB 66", frequency: 26_815),
			.init(name:"CB 67", frequency: 26_825),
			.init(name:"CB 68", frequency: 26_835),
			.init(name:"CB 69", frequency: 26_845),
			.init(name:"CB 70", frequency: 26_855),
			.init(name:"CB 71", frequency: 26_865),
			.init(name:"CB 72", frequency: 26_875),
			.init(name:"CB 73", frequency: 26_885),
			.init(name:"CB 74", frequency: 26_895),
			.init(name:"CB 75", frequency: 26_905),
			.init(name:"CB 76", frequency: 26_915),
			.init(name:"CB 77", frequency: 26_925),
			.init(name:"CB 78", frequency: 26_935),
			.init(name:"CB 79", frequency: 26_945),
			.init(name:"CB 80", frequency: 26_955),
		]

		return [
			.init(name: "PMR", channels: pmr, licensedComment: "PMR Radio only, please."),
			.init(name: "Freenet", channels: freenet, licensedComment: "Freenet Radio only, please."),
			.init(name: "CB", channels: cb, licensedComment: "CB Radio only, please."),
		]
	}
}
