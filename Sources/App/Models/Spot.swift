import Fluent
import Vapor

final class Spot: Model, Content, @unchecked Sendable {
	static let schema = "spots"

	enum SpotState : String, RawRepresentable, CaseIterable, Encodable, Decodable {
		case active
		case qrt
	}

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "activator_id")
	var activator: UserModel

	// User Model of person lending the training callsign used
	@OptionalParent(key: "activator_trainer_id")
	var activatorTrainer: UserModel?

	@Parent(key: "reference_id")
	var reference: Reference

	// Activator
	@Field(key: "station_callsign")
	var stationCallSign: String

	// Name of the logging operator (used for trainee contacts)
	@Field(key: "operator")
	var `operator`: String?

	@Field(key: "freq")
	var freq: Int

	@Field(key: "mode")
	var mode: QSO.Mode

	@Field(key: "state")
	var state: SpotState

	@Timestamp(key: "modification_date", on: .update)
	var modificationDate: Date?

	init() { }

	init(id: UUID? = nil, activator: UserModel, activatorTrainer: UserModel?, reference: Reference, stationCallSign: String, operator: String?, freq: Int, mode: QSO.Mode, state: SpotState, modificationDate: Date?) throws {
		self.id = id
		self.$activator.id = try activator.requireID()
		self.$activatorTrainer.id = try activatorTrainer?.requireID()
		self.$reference.id = try reference.requireID()
		self.stationCallSign = stationCallSign
		self.operator = `operator`
		self.freq = freq
		self.mode = mode
		self.state = state
		self.modificationDate = modificationDate
	}
}
