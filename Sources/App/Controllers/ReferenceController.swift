import FluentKit
import FluentSQL
import Vapor

struct ReferenceController: RouteCollection {
	let namingTheme: NamingTheme
	func boot(routes: RoutesBuilder) throws {
		let api = routes.grouped("api", "reference")
		api.get(use: index).description("List all references. No Auth required. Since this rarely changes, you shouldn't need to call this API very often.")
//		api.post(use: create)
//		api.group(":referenceId") { todo in
//			todo.delete(use: delete)
//		}

		let reference = routes.grouped(namingTheme.referenceSlugPathComponent)
		reference.get { req async throws -> View in
			let references = try await index(req: req)
			struct ReferenceContent: Content, CommonContentProviding {
				let references: [Reference]
				let common: CommonContent
			}
			return try await req.view.render("references", ReferenceContent(references: references, common: req.commonContent))
		}
		reference.group(":referenceId") { reference in
			reference.get { req async throws -> View in
				let refModel = try await specific(req: req)

				return try await specific(req: req, reference: refModel)
			}
		}
	}
	
	func index(req: Request) async throws -> [Reference] {
		try await Reference.query(on: req.db).all()
	}
	
	func specific(req: Request) async throws -> Reference {
		guard let refId = req.parameters.get("referenceId"),
			  let reference = try await Reference.query(on: req.db)
			.filter(\.$title, .equal, refId)
			.first()
			.get() else {
			throw Abort(.notFound)
		}
		return reference
	}

	func specific(req: Request, reference: Reference) async throws -> View {
		struct ReferenceQSOUserRankEntry: Codable {
			var callsign: String
			var count: Int
		}
		let activatorRank: [ReferenceQSOUserRankEntry]
		let hunterRank: [ReferenceQSOUserRankEntry]

		if let sql = req.db as? SQLDatabase {
			// The underlying database driver is SQL.
			let limit = 20
			activatorRank = try await sql.raw("SELECT station_callsign as callsign, COUNT(*) as count FROM qsos WHERE reference_id == \(literal: try reference.requireID().uuidString) GROUP BY callsign ORDER BY count DESC LIMIT \(literal: limit);").all(decoding: ReferenceQSOUserRankEntry.self)
			hunterRank = try await sql.raw("SELECT call as callsign, COUNT(*) as count FROM qsos WHERE reference_id == \(literal: try reference.requireID().uuidString) AND hunter_id NOT NULL GROUP BY callsign ORDER BY count DESC LIMIT \(literal: limit);").all(decoding: ReferenceQSOUserRankEntry.self)
		} else {
			activatorRank = []
			hunterRank = []
		}

		struct ReferenceContent: Content, CommonContentProviding {
			let reference: Reference
			let activators: [ReferenceQSOUserRankEntry]
			let hunters: [ReferenceQSOUserRankEntry]
			let common: CommonContent
		}

		return try await req.view.render("reference", ReferenceContent(reference: reference, activators: activatorRank, hunters: hunterRank, common: req.commonContent))
	}

	func create(req: Request) async throws -> Reference {
		let reference = try req.content.decode(Reference.self)
		try await reference.save(on: req.db)
		return reference
	}
	
	func delete(req: Request) async throws -> HTTPStatus {
		guard let reference = try await Reference.find(req.parameters.get("referenceId"), on: req.db) else {
			throw Abort(.notFound)
		}
		try await reference.delete(on: req.db)
		return .noContent
	}
}
