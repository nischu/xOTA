

import LeafKit

struct URLEncodeHostAllowedTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		guard let str = ctx.parameters.first?.string else {
			throw "unable to URL escape unexpected data"
		}
		return .string(str.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed))
	}
}

struct FrequencyFormatterTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		guard let frequencykHz = ctx.parameters.first?.int else {
			throw "Unable to format unexpected data. Expected int with kHz value"
		}
		return .string("\(frequencykHz/1000).\(String.init(format: "%03d", frequencykHz%1000)) MHz")
	}
}

