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

		// Awards
		let awards = authedAdmin.grouped("awards")
		awards.get(use: awards(req:)).description("admin only")
		awards.post("schedule", use: dispatchAwardCheck).description("admin only")
		awards.post("render", use: dispatchRender).description("admin only")
		awards.post("rerender-kind", use: dispatchRenderAll).description("admin only")
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
		let users = try await UserModel.query(on: req.db).with(\.$callsign).all()

		return try await req.view.render("admin/users", UsersContent(users: users, common: req.commonContent))
	}

	func actionPath(for user: UserModel) throws -> String {
		return "/admin/user/edit/\(try user.requireID())"
	}

	struct UserContent: Codable {
		let user: UserModel
		let credentials: [UserCredential]
		let error: String?
		let success: String?
		let actionPath: String
		let common: CommonContent
	}

	func editUser(req: Request) async throws -> View {

		guard let userID = req.parameters.get("userId"),
			  let userUUID = UUID(uuidString:userID),
			  let user = try await UserModel.query(on:req.db).filter(\.$id == userUUID).with(\.$callsign).first() else {
			throw Abort(.notFound)
		}

		let credentials = try await UserCredential.query(on: req.db).filter(\.$user.$id == userUUID).all()

		return try await req.view.render("admin/user_edit", UserContent(user: user, credentials: credentials, error: nil, success: nil, actionPath: actionPath(for: user), common: req.commonContent))
	}

	func updateUser(req: Request) async throws -> View {
		guard let userID = req.parameters.get("userId"),
			  let userUUID = UUID(uuidString:userID),
			  let user = try await UserModel.query(on:req.db).filter(\.$id == userUUID).with(\.$callsign).first() else {
			throw Abort(.notFound)
		}

		let credentials = try await UserCredential.query(on: req.db).filter(\.$user.$id == userUUID).all()

		struct FormContent: Codable {
			let callsign: String
			let authProvider: [String : String]
			let loginIdentifier: [String : String]
			let additionalInfo: [String : String]
		}
		let formContent = try req.content.decode(FormContent.self)
		var message = ""

		let callsignChanged = user.callsign.callsign != normalizedCallsign(formContent.callsign)
		if callsignChanged {
			user.callsign.callsign = normalizedCallsign(formContent.callsign)
			message += "updated callsign, "
		}

		var changedCredentials: [UserCredential] = []
		for credential in credentials {
			var changed = false
			let credentialID = try credential.requireID().uuidString
			if let provider = formContent.authProvider[credentialID],
				provider != credential.authProvider {
				credential.authProvider = provider
				changed = true
				message += "updated auth provider, "
			}
			if let loginIdentifier = formContent.loginIdentifier[credentialID],
			   loginIdentifier != credential.loginIdentifier {
				credential.loginIdentifier = loginIdentifier
				changed = true
				message += "updated login identifier, "
			}
			if let additionalInfo = formContent.additionalInfo[credentialID],
			   !additionalInfo.isEmpty {
				credential.additionalStorage = try Bcrypt.hash(additionalInfo)
				changed = true
				message += "updated additional storage as hashed value, "
			}
			if changed {
				changedCredentials.append(credential)
			}
		}

		if callsignChanged || !changedCredentials.isEmpty {
			try await req.db.transaction { [changedCredentials] db in
				for credential in changedCredentials {
					try await credential.save(on: db)
				}
				if callsignChanged {
					try await user.callsign.save(on: db)
				}
			}
			message += "saved."
		} else {
			message = "Nothing changed."
		}
		return try await req.view.render("admin/user_edit", UserContent(user: user, credentials:credentials, error: nil, success: message, actionPath: actionPath(for: user), common: req.commonContent))
	}

	// MARK: - Award

	func awards(req: Request) async throws -> View {
		struct AwardsContent: Codable {
			let awards: [Award]
			let users: [UserModel]
			let kinds: [String]
			let common: CommonContent
		}
		let awards = try await Award.query(on: req.db).with(\.$user).all()
		let users = try await UserModel.query(on: req.db).with(\.$callsign).all()
		let kinds = req.application.awardCheckers.map(\.awardKind)
		return try await req.view.render("admin/awards", AwardsContent(awards: awards, users: users, kinds: kinds, common: req.commonContent))
	}

	func dispatchAwardCheck(req: Request) async throws -> Response {
		struct AwardCheckForm: Codable {
			let userId: UserModel.IDValue
		}

		let formContent = try req.content.decode(AwardCheckForm.self)

		guard let user = try await UserModel.query(on:req.db).filter(\.$id == formContent.userId).with(\.$callsign).first() else {
			throw Abort(.notFound)
		}


		try await req.application.queues.queue.dispatch(CheckAwardElegibilityUser.self, CheckAwardElegibilityUserInfo(userId: user.requireID()))

		return req.redirect(to: "/admin/awards/")
	}

	func dispatchRender(req: Request) async throws -> Response {
		struct AwardForm: Codable {
			let awardId: Award.IDValue
		}

		let formContent = try req.content.decode(AwardForm.self)

		guard let award = try await Award.find(formContent.awardId, on: req.db) else {
			throw Abort(.notFound)
		}

		award.state = .waitingToRender
		try await award.save(on: req.db)

		try await req.application.queues.queue.dispatch(RenderAward.self, AwardInfo(awardId: award.requireID()))

		return req.redirect(to: "/admin/awards/")
	}

	func dispatchRenderAll(req: Request) async throws -> Response {
		struct AwardForm: Codable {
			let kind: String
		}

		let formContent = try req.content.decode(AwardForm.self)

		let awards = try await Award.query(on: req.db).filter(\.$kind == formContent.kind).all()
		for award in awards {
			award.state = .waitingToRender
			try await award.save(on: req.db)
			try await req.application.queues.queue.dispatch(RenderAward.self, AwardInfo(awardId: award.requireID()))
		}

		return req.redirect(to: "/admin/awards/")
	}


}
