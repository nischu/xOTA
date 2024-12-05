@testable import xOTA_App

import Fluent
import Testing
import XCTVapor

@Suite("App Tests with DB", .serialized)
struct AppTests {
	private func withApp(_ test: (Application) async throws -> ()) async throws {
		let app = try await Application.make(.testing)
		do {
			try await configure(app)
			try await app.autoMigrate()
			try await test(app)
		}
		catch {
			try await app.asyncShutdown()
			throw error
		}
		try await app.asyncShutdown()
	}

	@Test("Test Rules Route")
	func rules() async throws {
		try await withApp { app in
			try await app.test(.GET, "rules") { res async in
				#expect(res.status == .ok)
				#expect(res.body.string.contains("Toilets on the Air (TOTA) is intended as an amateur radio activity during"))
			}
		}
	}

}
