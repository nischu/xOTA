import Fluent
import FluentKit
import FluentSQL

extension QSO {
	struct BandDefinition: Codable {
		let low: Int
		let high: Int?
		let name: String

		func sqliteCaseWhenStatement(column: SQLQueryString) -> SQLQueryString {
			if let high {
				"WHEN \(column) BETWEEN \(literal: low) AND \(literal: high) THEN \(literal: name)"
			} else {
				"WHEN \(column) >= \(literal: low) THEN \(literal: name)"
			}
		}
	}

	static func bandDefinitions() -> [BandDefinition] {
		[
			.init(low: 135, high: 138, name: "2.2 km"),
			.init(low: 472, high: 479, name: "630 m"),
			.init(low: 1810, high: 2000, name: "160 m"),
			.init(low: 5351, high: 5367, name: "60 m"),
			.init(low: 7000, high: 7200, name: "40 m"),
			.init(low: 10100, high: 10150, name: "30 m"),
			.init(low: 14000, high: 14350, name: "20 m"),
			.init(low: 18068, high: 18168, name: "17 m"),
			.init(low: 21000, high: 21450, name: "15 m"),
			.init(low: 24890, high: 24990, name: "12 m"),
			.init(low: 28000, high: 29700, name: "10 m"),
			.init(low: 50000, high: 52000, name: "6 m"),
			.init(low: 70150, high: 70210, name: "4 m"),
			.init(low: 144000, high: 146000, name: "2 m"),
			.init(low: 430000, high: 440000, name: "70 cm"),
			.init(low: 1240000, high: 1300000, name: "23 cm"),
			.init(low: 2320000, high: 2450000, name: "13 cm"),
			.init(low: 3400000, high: 3475000, name: "9 cm"),
			.init(low: 5650000, high: 5850000, name: "6 cm"),
			.init(low: 10000000, high: 10500000, name: "3 cm"),
			.init(low: 24000000, high: 24250000, name: "1.2 cm"),
			.init(low: 47000000, high: nil, name: "sub cm"),

			.init(low: 26565, high: 27405, name: "CB"),
			.init(low: 149025, high: 149113, name: "Freenet"),
			.init(low: 446006, high: 446193, name: "PMR"),
		]
	}

	static func bandCaseStatement(as rowName: SQLQueryString) -> SQLQueryString {
		"""
		CASE
			\(Self.bandDefinitions().map { $0.sqliteCaseWhenStatement(column: "freq")}.joined(separator: "\n"))
			ELSE 'N/A'
		END AS \(rowName)
		"""
	}

}

