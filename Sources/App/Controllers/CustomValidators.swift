import Vapor

// MARK: - Callsign

extension ValidatorResults {
	public struct Callsign {
		public let isValidCallsign: Bool
	}
}

extension ValidatorResults.Callsign: ValidatorResult {
	public var isFailure: Bool {
		!self.isValidCallsign
	}

	public var successDescription: String? {
		"is a valid callsign"
	}

	public var failureDescription: String? {
		"is not a valid callsign"
	}
}


internal func normalizedCallsign(_ string: String) -> String {
	string.uppercased()
}
internal func normalizedCallsignOptional(_ string: String?) -> String? {
	guard let string else { return nil }
	return normalizedCallsign(string)
}

private let callsignRegexString = "(^([A-Z0-9]{2,3}\\/)?([A-Z0-9]{1,2}[0-9]{1}[A-Z]{1,4})(\\/[A-Z0-9])?$)"


extension Validator where T == String {
	/// Validates whether a `String` is a valid callsign.
	public static var callsign: Validator<T> {
		.init { input in
			let input = normalizedCallsign(input)
			guard let range = input.range(of: callsignRegexString, options: [.regularExpression]),
				  range.lowerBound == input.startIndex && range.upperBound == input.endIndex
			else {
				return ValidatorResults.Callsign(isValidCallsign: false)
			}
			return ValidatorResults.Callsign(isValidCallsign: true)
		}
	}
	public static var relaxedCallsign: Validator<T> {
		.init { data in
			(.count(3...10) && .characterSet(.alphanumerics.union(CharacterSet(charactersIn: "/")))).validate(data)
		}
	}

}


// MARK: - Date

extension ValidatorResults {
	public struct DateInPast {
		public let isValidDateInPast: Bool
	}
}

extension ValidatorResults.DateInPast: ValidatorResult {
	public var isFailure: Bool {
		!self.isValidDateInPast
	}

	public var successDescription: String? {
		"is a valid date in paste"
	}

	public var failureDescription: String? {
		"is not a valid date in past"
	}
}

extension Validator where T == String {
	/// Validates whether a `String` is a valid zip code.
	public static var dateInPast: Validator<T> {
		.init { input in
			let formatter = ISO8601DateFormatter()
			formatter.formatOptions.remove(.withTimeZone)
			guard let date = formatter.date(from: input),
				  date < Date()
			else {
				return ValidatorResults.DateInPast(isValidDateInPast: false)
			}
			return ValidatorResults.DateInPast(isValidDateInPast: true)
		}
	}
}

