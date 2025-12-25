
import Fluent
import Foundation
import Testing
import Vapor

@testable import xOTA_App

@Suite("AwardQueryHelper tests with DB", .serialized)
struct AwardQueryHelperTests: AppQueueTests {
	@Test("AwardQueryHelper returns correct bands")
	func testBandMapping() async throws {
		try await withApp { app in
			let db = app.db
			let activatorCall = "DA1TEST"
			let user = try await UserModel.createUser(
				with: activatorCall,
				kind: .licensed,
				on: db
			)

			app.logger.logLevel = .debug

			let refName = "T-01"
			let referenceT01 = try #require(
				await Reference.query(on: db).filter(\.$title, .equal, refName)
					.first()
			)

			try await addQSO(on: db, stationCall: activatorCall, reference: refName, call: "DH1TEST", mode: .FM, freq: 1297_500)
			try await addQSO(on: db, stationCall: activatorCall, reference: refName, call: "DH1TEST", mode: .FM, freq: 430_200)
			try await addQSO(on: db, stationCall: activatorCall, reference: refName, call: "DH1TEST", mode: .FM, freq: 1297_500)
			try await addQSO(on: db, stationCall: activatorCall, reference: refName, call: "DH1TEST", mode: .SSB, freq: 29_100)

			try await addQSO(on: db, stationCall: activatorCall, reference: "T-02", call: "DH1TEST", mode: .FM, freq: 145_500)
			try await addQSO(on: db, stationCall: activatorCall, reference: "T-02", call: "DH1TEST", mode: .FM, freq: 144_000)
			try await addQSO(on: db, stationCall: activatorCall, reference: "T-02", call: "DH1TEST", mode: .FM, freq: 146_000)

			#expect(try await AwardQueryHelper().activatedBands(for: user, app: app, referenceIds: [referenceT01.requireID()]) == ["10 m", "70 cm", "23 cm"])

			#expect(try await AwardQueryHelper().activatedBands(for: user, app: app, referenceIds: [referenceT01.requireID()], mode: .FM) == ["70 cm", "23 cm"])

			let referenceT02 = try #require(
				await Reference.query(on: db).filter(\.$title, .equal, "T-02")
					.first()
			)
			let bandsT02 = try await AwardQueryHelper().activatedBands(for: user, app: app, referenceIds: [referenceT02.requireID()])
			#expect(bandsT02 == ["2 m"])

			#expect(try await AwardQueryHelper().activatedBands(for: user, app: app, referenceIds: []) == ["10 m", "2 m", "70 cm", "23 cm"])

			#expect(try await AwardQueryHelper().activatedBands(for: user, app: app, referenceIds: nil) == ["10 m", "2 m", "70 cm", "23 cm"])

			try await addQSO(on: db, stationCall: activatorCall, reference: "T-02", call: "DH1TEST", mode: .FM, freq: 47_000_000)

			try await addQSO(on: db, stationCall: activatorCall, reference: "T-02", call: "DH1TEST", mode: .FM, freq: 135)

			#expect(try await AwardQueryHelper().activatedBands(for: user, app: app, referenceIds: nil) == ["2.2 km", "10 m", "2 m", "70 cm", "23 cm", "sub cm"])
		}
	}

	@Test("AwardQueryHelper returns correct reference/band groups")
	func testReferenceBandMapping() async throws {
		try await withApp { app in
			let db = app.db
			let activatorCall = "DA1TEST"
			let user = try await UserModel.createUser(
				with: activatorCall,
				kind: .licensed,
				on: db
			)

			app.logger.logLevel = .debug

			let refName = "T-01"
			let referenceT01 = try #require(
				await Reference.query(on: db).filter(\.$title, .equal, refName)
					.first()
			)

			try await addQSO(on: db, stationCall: activatorCall, reference: refName, call: "DH1TEST", mode: .FM, freq: 1297_500)
			try await addQSO(on: db, stationCall: activatorCall, reference: refName, call: "DH1TEST", mode: .FM, freq: 430_200)
			try await addQSO(on: db, stationCall: activatorCall, reference: refName, call: "DH1TEST", mode: .FM, freq: 1297_500)
			try await addQSO(on: db, stationCall: activatorCall, reference: refName, call: "DH1TEST", mode: .SSB, freq: 29_100)

			try await addQSO(on: db, stationCall: activatorCall, reference: "T-02", call: "DH1TEST", mode: .FM, freq: 145_500)
			let referenceT02 = try #require(
				await Reference.query(on: db).filter(\.$title, .equal, "T-02")
					.first()
			)
			let bandsT02 = try await AwardQueryHelper().activatedBands(for: user, app: app, referenceIds: [referenceT02.requireID()])
			#expect(bandsT02 == ["2 m"])

			#expect(
				try await AwardQueryHelper().activatedBandsPerReference(for: user, app: app, referenceIds: [referenceT01.requireID(), referenceT02.requireID()])
				==
				[
					referenceT01.requireID().uuidString: ["10 m", "70 cm", "23 cm"],
					referenceT02.requireID().uuidString: ["2 m"]
				]
			)
		}

	}
}
