import Fluent
import Vapor

final class Callsign: Model, Content, @unchecked Sendable {
	static let schema = "callsigns"

	enum CallsignKind: String, RawRepresentable, Content {
		case licensed = "licensed"
		case unlicensed = "unlicensed"
		case training = "training"
	}

	@ID(key: .id)
	var id: UUID?

	@Field(key: "callsign")
	var callsign: String

	@Parent(key: "user_id")
	var user: UserModel

	@Field(key: "kind")
	var kind: CallsignKind


	init() { }

	init(id: Callsign.IDValue? = nil,
		 callsign: String, kind: CallsignKind) {
		self.id = id
		self.callsign = callsign
		self.kind = kind
	}

	static func callsign(_ callsign: String, on database: any Database) -> QueryBuilder<Callsign> {
		return Callsign.query(on: database)
			.filter(\.$callsign == normalizedCallsign(callsign))
	}
}
