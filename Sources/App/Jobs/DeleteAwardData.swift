import Foundation
import Queues

struct AwardDelteInfo: Codable {
	let awardId: Award.IDValue
	let filename: String
}

struct DeleteAwardData: AsyncJob {
	typealias Payload = AwardDelteInfo

	func dequeue(_ context: Queues.QueueContext, _ payload: Payload) async throws {
		let filename = payload.filename
		guard !filename.isEmpty else {
			throw "Tried to delete award info with empty filename \(payload)."
		}
		let fileManager = FileManager.default
		let renderPath = RenderAward.renderPath(for: payload.filename)
		var fileURL = URL(fileURLWithPath: renderPath)
		try fileManager.removeItem(at: fileURL)
		fileURL.deleteLastPathComponent()
		if fileURL.lastPathComponent == payload.awardId.uuidString {
			try fileManager.removeItem(at: fileURL)
		}

	}
}
