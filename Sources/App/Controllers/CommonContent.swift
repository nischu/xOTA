import Vapor

extension Request {
	var commonContent: CommonContent {
		let hasUser = auth.has(UserModel.self)
		return CommonContent(hasUser: hasUser, namingTheme: application.namingTheme, loggingDisabled: CommonContent.loggingDisabled)
	}
}

struct CommonContent: Codable {
	let hasUser: Bool
	let namingTheme: NamingTheme
	var loggingDisabled: Bool
	static var loggingDisabled: Bool {
		return Environment.get("LOGGING_DISABLED") != nil
	}
}

protocol CommonContentProviding {
	var common: CommonContent { get }
}


struct NamingTheme: Codable {
	let referenceSlug: String
	let referenceSingular: String
	let referencePlural: String

	static var `default`: NamingTheme {
		return NamingTheme(referenceSlug: "reference", referenceSingular: "Reference", referencePlural: "References")
	}
	var referenceSlugPathComponent: PathComponent {
		PathComponent(stringLiteral: referenceSlug)
	}
}


struct NamingThemeKey: StorageKey {
	typealias Value = NamingTheme
}

extension Application {

	var namingTheme: NamingTheme {
		get {
			self.storage[NamingThemeKey.self] ?? NamingTheme.default
		}
		set {
			self.storage[NamingThemeKey.self] = newValue
		}
	}
}


import LeafKit

struct URLEncodeHostAllowedTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		guard let str = ctx.parameters.first?.string else {
			throw "unable to URL escape unexpected data"
		}
		return .string(str.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed))
	}
}

