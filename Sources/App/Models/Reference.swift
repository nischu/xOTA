import Fluent
import Vapor

final class Reference: Model, Content, @unchecked Sendable {
	static let schema = "references"

	@ID(key: .id)
	var id: UUID?
	
	@Field(key: "title")
	var title: String
	@Field(key: "website")
	var website: String

	@Field(key: "embed_map")
	var embedMap: String?

	@Children(for: \.$reference)
	var qsos: [QSO]

	init() { }
	
	init(id: UUID? = nil, title: String, website: String, embedMap: String? = nil) {
		self.id = id
		self.title = title
		self.website = website
		self.embedMap = embedMap
	}
}
