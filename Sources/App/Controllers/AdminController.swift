import Fluent
import FluentKit
import FluentSQL
import Vapor

struct AdminController: RouteCollection {
	let authMiddleware: [Middleware]
	let namingTheme: NamingTheme

	func boot(routes: RoutesBuilder) throws {

		let authedAdmin = routes.grouped(authMiddleware).grouped("admin")
		authedAdmin.get { req in
			return try await req.view.render("admin/index", ["common": req.commonContent])
		}

		// References
		authedAdmin.get(namingTheme.referenceSlugPathComponent, use: references)
		authedAdmin.get(namingTheme.referenceSlugPathComponent, "create", use: createReference)
		authedAdmin.post(namingTheme.referenceSlugPathComponent, "create", use: updateReference)
		authedAdmin.get(namingTheme.referenceSlugPathComponent, "edit", ":referenceId", use: editReference)
		authedAdmin.post(namingTheme.referenceSlugPathComponent, "edit", ":referenceId", use: updateReference)
		authedAdmin.post(namingTheme.referenceSlugPathComponent, "delete", ":referenceId", use: deleteReference)

		// Users
		authedAdmin.get("user", use: users).description("admin only")
		authedAdmin.get("user", "edit", ":userId", use: editUser).description("admin only")
		authedAdmin.post("user", "edit", ":userId", use: updateUser).description("admin only")

	}

	func references(req: Request) async throws -> View {
		struct ReferencesContent: Codable {
			let references: [Reference]
			let common: CommonContent
		}
		let references = try await Reference.query(on: req.db).all()

		return try await req.view.render("admin/references", ReferencesContent(references: references, common: req.commonContent))
	}

	struct ReferenceContent: Codable {
		let reference: Reference?
		let error: String?
		let success: String?
		let actionPath: String
		let actionName: String
		let deletePath: String?
		let common: CommonContent
	}

	enum EditAction: String {
		case create = "create"
		case edit = "edit"
		case delete = "delete"
	}

	func editPath(for reference: Reference, action: EditAction = .edit) throws -> String {
		switch action {
		case .create:
			return createPath()
		case .edit:
			fallthrough
		case .delete:
			return "/admin/\(namingTheme.referenceSlug)/\(action.rawValue)/\(try reference.requireID())"
		}
	}

	func createPath() -> String {
		"/admin/\(namingTheme.referenceSlug)/\(EditAction.create)/"
	}


	func createReference(req: Request) async throws -> View {
		return try await req.view.render("admin/reference_edit", ReferenceContent(reference: nil, error: nil, success: nil, actionPath: createPath(), actionName: "Create", deletePath: nil, common: req.commonContent))
	}

	func editReference(req: Request) async throws -> View {
		guard let reference = try await Reference.find(req.parameters.get("referenceId"), on: req.db) else {
			throw Abort(.notFound)
		}
		return try await req.view.render("admin/reference_edit", ReferenceContent(reference: reference, error: nil, success: nil, actionPath: try editPath(for: reference), actionName: "Save", deletePath: editPath(for: reference, action: .delete), common: req.commonContent))
	}

	func updateReference(req: Request) async throws -> View {
		struct FormContent: Codable {
			let title: String
			let website: String
		}

		let formContent = try req.content.decode(FormContent.self)

		let successMessage: String
		var reference: Reference
		if let referenceId: UUID = req.parameters.get("referenceId") {
			guard let ref = try await Reference.find(referenceId, on: req.db) else {
				throw Abort(.notFound)
			}
			reference = ref
			successMessage = "Sucessfully updated \(namingTheme.referenceSingular)."
		} else {
			reference = Reference.init()
			successMessage = "Sucessfully created \(namingTheme.referenceSingular)."
		}
		// TODO: verify there isn't a duplicate title.
		reference.title = formContent.title
		reference.website = formContent.website

		try await reference.save(on: req.db)
		return try await req.view.render("admin/reference_edit", ReferenceContent(reference: reference, error: nil, success: successMessage, actionPath: try editPath(for: reference), actionName: "Save", deletePath: try editPath(for: reference, action: .delete), common: req.commonContent))
	}

	func deleteReference(req: Request) async throws -> View {
		guard let reference = try await Reference.find(req.parameters.get("referenceId"), on: req.db) else {
			throw Abort(.notFound)
		}
		// TODO: delete associated QSOs
		try await reference.delete(on: req.db)
		return try await req.view.render("admin/reference_edit", ReferenceContent(reference: reference, error: nil, success: "Successfully deleted \(namingTheme.referenceSingular).", actionPath: try editPath(for: reference, action: .create), actionName: "Create", deletePath: nil, common: req.commonContent))
	}

	// MARK: - User

	func users(req: Request) async throws -> View {
		struct UsersContent: Codable {
			let users: [UserModel]
			let common: CommonContent
		}
		let users = try await UserModel.query(on: req.db).all()

		return try await req.view.render("admin/users", UsersContent(users: users, common: req.commonContent))
	}

	func actionPath(for user: UserModel) throws -> String {
		return "/admin/user/edit/\(try user.requireID())"
	}

	struct UserContent: Codable {
		let user: UserModel
		let error: String?
		let success: String?
		let actionPath: String
		let common: CommonContent
	}

	func editUser(req: Request) async throws -> View {
		guard let user = try await UserModel.find(req.parameters.get("userId"), on: req.db) else {
			throw Abort(.notFound)
		}
		return try await req.view.render("admin/user_edit", UserContent(user: user, error: nil, success: nil, actionPath: actionPath(for: user), common: req.commonContent))
	}

	func updateUser(req: Request) async throws -> View {
		guard let user = try await UserModel.find(req.parameters.get("userId"), on: req.db) else {
			throw Abort(.notFound)
		}

		struct FormContent: Codable {
			let callsign: String
			let ccchubUser: String
			let password: String
		}

		let formContent = try req.content.decode(FormContent.self)

		user.callsign = formContent.callsign
		user.ccchubUser = formContent.ccchubUser.isEmpty ? nil : formContent.ccchubUser
		var success = "Successfully updated user."
		if !formContent.password.isEmpty {
			user.hashedPassword = try Bcrypt.hash(formContent.password)
			success = "Successfully updated user and password."
		}
		try await user.save(on: req.db)

		return try await req.view.render("admin/user_edit", UserContent(user: user, error: nil, success: success, actionPath: actionPath(for: user), common: req.commonContent))
	}

}
