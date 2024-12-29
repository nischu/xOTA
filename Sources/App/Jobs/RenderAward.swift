import Vapor
import Foundation
import Queues

struct AwardInfo: Codable {
	let awardId: Award.IDValue
}

struct RenderAward: AsyncJob {
	typealias Payload = AwardInfo

	static func renderPath(for filename: String) -> String {
		"Public/\(filename)"
	}

	var formatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()

	func dequeue(_ context: QueueContext, _ payload: Payload) async throws {
		let db = context.application.db
		guard let award = try await Award.query(on: db)
			.filter(\.$id, .equal, payload.awardId)
			.with(\.$user, { user in
				user.with(\.$callsign)
			})
				.first()
		else {
			context.logger.error("Failed to find award with id \(payload.awardId) for award rendering.")
			return
		}

		let userCallsign = award.user.callsign.callsign
		let renderPathPrefix = try "rendered-awards/\(award.requireID().uuidString)/"
		let filename: String
		if let _filename = award.filename, _filename.hasPrefix(renderPathPrefix) {
			filename = _filename
		} else {
			filename = "\(renderPathPrefix)\(award.filename ?? userCallsign).pdf"
			award.filename = filename
		}
		award.state = .rendering
		try await award.save(on: db)
		let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
		let scriptURL = URL(fileURLWithPath: "awards/award.sh", relativeTo: currentDirectory)
		let renderPath = Self.renderPath(for: filename)

		var env = ProcessInfo.processInfo.environment
		env["AWARD_DATE"] = formatter.string(from: award.issueDate)
		let process = Process()
		let pipe = Pipe()
		process.executableURL = scriptURL
		process.standardOutput = pipe.fileHandleForWriting
		process.standardError = pipe.fileHandleForWriting
		process.environment = env
		process.arguments = [
			userCallsign,
			award.kind,
			renderPath
		]

		// cancel the award render process after 30s
		let cancelOnTimeout = Task.detached {
			try await Task.sleep(for: Duration.seconds(30))
			process.terminate()
		}

		try process.run()
		process.waitUntilExit()

		pipe.fileHandleForWriting.closeFile()
		let processOut = pipe.fileHandleForReading.readDataToEndOfFile()
		pipe.fileHandleForReading.closeFile()

		cancelOnTimeout.cancel()
		if process.terminationStatus == 0 {
			award.state = .issued
			try await award.save(on: db)
		} else {
			context.logger.error("Failed to render award: \(String(describing: String(data: processOut, encoding: .utf8)))")
		}
	}

	func error(_ context: QueueContext, _ error: any Error, _ payload: Payload) async throws {

	}
}
