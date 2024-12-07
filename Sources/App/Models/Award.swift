import Fluent
import Vapor

final class Award: Model, Content, @unchecked Sendable {
	static let schema = "awards"

	enum AwardKind: String, RawRepresentable, Content {
		case activatedAll = "activated-all"
		case huntedAll = "hunted-all"
	}

	enum State: String, RawRepresentable, Content {
		case waitingToRender = "waiting-to-render"
		case rendering = "rendering"
		case issued = "issued"
	}

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "user_id")
	var user: UserModel

	@Field(key: "kind")
	var kind: AwardKind

	@Field(key: "state")
	var state: State

	@Field(key: "filename")
	var filename: String?

	init() { }

	init(id: Award.IDValue? = nil,
		 userId: UserModel.IDValue, kind: AwardKind) {
		self.id = id
		self.$user.id = userId
		self.kind = kind
		self.state = .waitingToRender
	}
}
