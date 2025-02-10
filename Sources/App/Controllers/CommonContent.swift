import Vapor

extension Request {
	var commonContent: CommonContent {
		let hasUser = auth.has(UserModel.self)
		return CommonContent(hasUser: hasUser, namingTheme: application.namingTheme, loggingDisabled: CommonContent.loggingDisabled, devInstance: CommonContent.devInstance)
	}
}

struct CommonContent: Codable {
	let hasUser: Bool
	let namingTheme: NamingTheme
	var loggingDisabled: Bool
	static var loggingDisabled: Bool {
		return Environment.get("LOGGING_DISABLED") != nil
	}
	var devInstance: Bool
	static var devInstance: Bool {
		return Environment.get("DEV") != nil
	}
}

protocol CommonContentProviding {
	var common: CommonContent { get }
}


struct NamingTheme: Codable {
	let activityName: String
	let adifSIG: String
	let referenceSlug: String
	let referenceSingular: String
	let referencePlural: String
	let activityHostname: String?

	static var `default`: NamingTheme {
		return NamingTheme(activityName:"xOTA", adifSIG: "xOTA", referenceSlug: "reference", referenceSingular: "Reference", referencePlural: "References", activityHostname: nil)
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

