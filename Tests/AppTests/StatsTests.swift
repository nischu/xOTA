import Fluent
import Testing
import XCTVapor

@testable import xOTA_App

@Suite("Test stats page", .serialized)
struct StatsTests: AppQueueTests {

	@Test(
		"Stats include licensed hunter callsign even if operator name was logged"
	)
	func rules() async throws {
		try await withApp { app in
			let db = app.db
			let hunterCall = "DH1TEST"
			_ = try await UserModel.createUser(
				with: hunterCall,
				kind: .licensed,
				on: db
			)
			let activatorCall = "DA0TEST"
			_ = try await UserModel.createUser(
				with: activatorCall,
				kind: .licensed,
				on: db
			)
			try await addQSO(
				on: db,
				stationCall: activatorCall,
				reference: "T-01",
				call: hunterCall,
				contactedOperator: "HUNTER1TEST",
				mode: .SSB
			)
			try await app.test(.GET, "stats/?no-cache=1") { res async in
				#expect(res.status == .ok)
				let bodyString = res.body.string
				#expect(
					bodyString.contains(hunterCall)
						&& !bodyString.contains("HUNTER1TEST"),
					"Got body:\(bodyString)"
				)
			}
		}
	}
}
