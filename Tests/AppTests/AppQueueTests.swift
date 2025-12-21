import Queues
import XCTQueues
import XCTVapor

@testable import xOTA_App

protocol AppQueueTests {}
extension AppQueueTests {
	func withApp(_ test: (Application) async throws -> Void) async throws {
		let app = try await Application.make(.testing)
		do {
			app.queues.use(.asyncTest)
			try await configure(app)
			try await app.autoMigrate()
			try await test(app)
		} catch {
			try await app.asyncShutdown()
			throw error
		}
		try await app.asyncShutdown()
	}
}
