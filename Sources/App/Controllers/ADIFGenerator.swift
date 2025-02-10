import Foundation

protocol ADIFGeneratorQSO {
	var date: Date { get }
	var call: String { get }
	var contactedOperator: String? { get }
	var stationCallsign: String { get }
	var `operator`: String? { get }
	var freq: Int { get } // in kHz
	var mode: String { get }
	var rstSent: String? { get }
	var rstRcvt: String? { get }
	var sigInfo: String? { get }
	var mySigInfo: String? { get }
}

extension ADIFGeneratorQSO {
	func records(with SIG: String) -> [ADIFGenerator.Record] {
		var records: [ADIFGenerator.Record?] = [
			.init(name: .stationCallsign, value: stationCallsign),
			.init(name: .operator, value: `operator`, nilOnEmpty: true),
			.init(name: .call, value: call),
			.init(name: .contactedOp, value: contactedOperator, nilOnEmpty: true),
			.init(date: date),
			.init(time: date),
			.init(freq: freq),
			.init(name: .mode, value: mode),
			.init(name: .rstRcvd, value: rstRcvt),
			.init(name: .rstSent, value: rstSent),
		]
		
		if let sigInfo {
			records.append(.init(name: .sig, value: SIG))
			records.append(.init(name: .sigInfo, value: sigInfo))
		}
		if let mySigInfo {
			records.append(.init(name: .mySig, value: SIG))
			records.append(.init(name: .mySigInfo, value: mySigInfo))
		}
		return records.compactMap { $0 }
	}
}

struct ADIFGenerator: CustomStringConvertible {

	var headerComment: String?
	var specialInterestGroup: String

	var adifVersion: String = "3.1.4"
	var programmId: String = "xOTA"
	var programVersion: String = "totawatch.de"
	var createdDate: Date = Date()

	var qsos: [ADIFGeneratorQSO]

	init(headerComment: String? = nil, programVersion: String, specialInterestGroup: String, qsos: [ADIFGeneratorQSO]) {
		self.headerComment = headerComment
		self.programVersion = programVersion
		self.specialInterestGroup = specialInterestGroup
		self.qsos = qsos
	}

	var description: String {

		let headerRecords: [Record] = [
			.init(name: .adifVersion, value: adifVersion),
			.init(name: .programId, value: programmId),
			.init(name: .programVersion, value: programVersion),
			.init(name: .createdTimestamp, value: "\(Record.dateFormatter.string(from: createdDate)) \(Record.timeFormatter.string(from: createdDate))"),
			.init(name: .eoh, value: "")
		]
		var headerString: String = ""
		if let headerComment {
			headerString.append(headerComment)
			headerString.append("\n\n")
		}
		headerString.append(string(for: headerRecords))
		headerString.append("\n\n")
		return qsos.reduce(headerString) { partialResult, qso in
			partialResult + string(for: qso.records(with: specialInterestGroup) + [Record.init(name: .eor, value: "")]) + "\n"
		}
	}

	func string(for records: [Record]) -> String {
		records.reduce(into: "") { partialResult, rec in
			partialResult.append(String(describing: rec))
		}
	}

	struct Record: CustomStringConvertible {
		var name: Field
		var value: String

		var description: String {
			let count = value.count
			if count > 0 {
				return "<\(name.rawValue):\(value.count)>\(value)\n"
			} else {
				return "<\(name.rawValue)>\n"
			}
		}

		init?(name: Field, value: String?, nilOnEmpty: Bool = false) {
			guard let value, (!value.isEmpty || !nilOnEmpty)  else {
				return nil
			}
			self.init(name: name, value: value)
		}

		init(name: Field, value: String) {
			self.name = name
			self.value = value
		}

		init(time: Date) {
			self.init(name: .qsoTime, value: Self.timeFormatter.string(from: time))
		}

		init(date: Date) {
			self.init(name: .qsoDate, value: Self.dateFormatter.string(from: date))
		}

		/// - Parameter freq: requency in kHz
		init(freq: Int) {
			let freqMHz = Double(freq)/1000
			let value = Self.numberFormatter.string(from:NSNumber(value: freqMHz))!
			self.init(name: .freq, value: value)
		}

		static let timeZone = TimeZone(secondsFromGMT: 0)
		static let dateFormatter = {
			let formatter = DateFormatter()
			formatter.dateFormat = "yyyyMMdd"
			formatter.timeZone = timeZone
			return formatter
		}()

		static let timeFormatter = {
			let formatter = DateFormatter()
			formatter.dateFormat = "HHmmss"
			formatter.timeZone = timeZone
			return formatter
		}()

		static let numberFormatter = {
			let formatter = NumberFormatter()
			formatter.localizesFormat = false
			formatter.numberStyle = .decimal
			formatter.decimalSeparator = "."
			formatter.hasThousandSeparators = false
			return formatter
		}()
	}

	enum Field: String, RawRepresentable {
		case adifVersion = "ADIF_VER"
		case programId = "PROGRAMID"
		case programVersion = "PROGRAMVERSION"
		case createdTimestamp = "CREATED_TIMESTAMP"

		case eoh = "EOH"
		case eor = "EOR"

		// the logging station's callsign (the callsign used over the air)
		case stationCallsign = "STATION_CALLSIGN"
		// the logging operator's callsign
		case `operator` = "OPERATOR"
		/// the contacted station's callsign
		case call = "CALL"
		/// the callsign of the individual operating the contacted station
		case contactedOp = "CONTACTED_OP"
		case mySig = "MY_SIG"
		case mySigInfo = "MY_SIG_INFO"
		case sig = "SIG"
		case sigInfo = "SIG_INFO"
		case qsoDate = "QSO_DATE"
		case qsoTime = "TIME_ON"
		case freq = "FREQ"
		case mode = "MODE"
		case rstRcvd = "RST_RCVD"
		case rstSent = "RST_SENT"
	}

}
