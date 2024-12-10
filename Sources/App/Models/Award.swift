import Fluent
import Vapor

final class Award: Model, Content, @unchecked Sendable {
	static let schema = "awards"

	typealias AwardKind = String

	enum State: String, RawRepresentable, Content {
		case waitingToRender = "waiting-to-render"
		case rendering = "rendering"
		case issued = "issued"
	}

	@ID(key: .id)
	var id: UUID?

	@Field(key: "name")
	var name: String

	@Parent(key: "user_id")
	var user: UserModel

	@Field(key: "kind")
	var kind: AwardKind

	@Field(key: "date_issued")
	var issueDate: Date

	@Field(key: "state")
	var state: State

	@Field(key: "filename")
	var filename: String?

	init() { }

	init(id: Award.IDValue? = nil,
		 userId: UserModel.IDValue, kind: AwardKind, name: String) {
		self.id = id
		self.name = name
		self.$user.id = userId
		self.kind = kind
		self.issueDate = Date()
		self.state = .waitingToRender
	}

	static func awardsQuery(for userId: UserModel.IDValue, on db: any Database) -> QueryBuilder<Award> {
		Award.query(on: db).filter(\.$user.$id == userId).sort(\.$issueDate, .descending)
	}

	static func awards(for userId: UserModel.IDValue, on db: any Database) async throws -> [Award] {
		try await self.awardsQuery(for: userId, on: db).all()
	}

}
