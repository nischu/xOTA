import Fluent
import Vapor

final class QSO: Model, Content, @unchecked Sendable {

	enum Mode : String, RawRepresentable, CaseIterable, Encodable, Decodable {
		case AM
		case ARDOP
		case ATV
		case CHIP
		case CLO
		case CONTESTI
		case CW
		case DIGITALVOICE
		case DOMINO
		case DYNAMIC
		case FAX
		case FM
		case FSK441
		case FT8
		case HELL
		case ISCAT
		case JT4
		case JT6M
		case JT9
		case JT44
		case JT65
		case MFSK
		case MSK144
		case MT63
		case OLIVIA
		case OPERA
		case PAC
		case PAX
		case PKT
		case PSK
		case PSK2K
		case Q15
		case QRA64
		case ROS
		case RTTY
		case RTTYM
		case SSB
		case SSTV
		case T10
		case THOR
		case THRB
		case TOR
		case V4
		case VOI
		case WINMOR
		case WSPR
	}

	static let schema = "qsos"

	@ID(key: .id)
	var id: UUID?

	@Parent(key: "activator_id")
	var activator: UserModel

	// User Model of person lending the training callsign used
	@OptionalParent(key: "activator_trainer_id")
	var activatorTrainer: UserModel?

	@OptionalParent(key: "hunter_id")
	var hunter: UserModel?

	@Parent(key: "reference_id")
	var reference: Reference

	@OptionalParent(key: "hunted_reference_id")
	var huntedReference: Reference?

	@Field(key: "date")
	var date: Date

	// Hunter/Contact
	@Field(key: "call")
	var call: String

	// Name of the contacted operator (used for trainee on other side of contact)
	@Field(key: "contacted_operator")
	var contactedOperator: String?

	// Activator
	@Field(key: "station_callsign")
	var stationCallSign: String

	// Name of the logging operator (used for trainee contacts)
	@Field(key: "operator")
	var `operator`: String?

	@OptionalParent(key: "contacted_operator_user_id")
	var contactedOperatorUser: UserModel?

	@Field(key: "freq")
	var freq: Int

	@Field(key: "mode")
	var mode: Mode

	@Field(key: "rst_sent")
	var rstSent: String?

	@Field(key: "rst_rcvd")
	var rstRcvt: String?

	@Timestamp(key: "modification_date", on: .update)
	var modificationDate: Date?

	init() { }

	init(id: UUID? = nil, activator: UserModel, activatorTrainer: UserModel?, hunter: UserModel?, reference: Reference, huntedReference: Reference? = nil, date: Date, call: String, stationCallSign: String, operator: String?, contactedOperator: String?, contactedOperatorUser: UserModel?, freq: Int, mode: Mode, rstSent: String, rstRcvt: String) throws {
		self.id = id
		self.$activator.id = try activator.requireID()
		self.$activatorTrainer.id = try activatorTrainer?.requireID()
		self.$hunter.id = try hunter?.requireID()
		self.$reference.id = try reference.requireID()
		self.$huntedReference.id = try huntedReference?.requireID()
		self.date = date
		self.call = call
		self.stationCallSign = stationCallSign
		self.operator = `operator`
		self.contactedOperator = contactedOperator
		self.$contactedOperatorUser.id = try contactedOperatorUser?.requireID()
		self.freq = freq
		self.mode = mode
		self.rstSent = rstSent
		self.rstRcvt = rstRcvt
	}
}
