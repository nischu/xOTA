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

	@Test("Test User Create with already logged hunter QSOs adds user reference.")
	func userCreationAfterQSOs() async throws {
		try await withApp { app in
			let db = app.db
			let userDL1TEST = try await UserModel.createUser(with: "DL1TEST", kind: .licensed, on: db)
			let reference = try #require(await Reference.query(on: db).filter(\.$title == "T-01").first())
			#expect(try await UserModel.userFor(callsign: "DL2TEST", on: db).get() == nil)
			var qso = try QSO(activator: userDL1TEST,
							  activatorTrainer: nil,
							  hunter: nil,
							  reference: reference,
							  date: Date(),
							  call: "DL2TEST",
							  stationCallSign: "DL1TEST",
							  operator: nil,
							  contactedOperator: "DL3TEST",
							  contactedOperatorUser: nil,
							  freq: 145_500,
							  mode: .FM,
							  rstSent: "59",
							  rstRcvt: "59")
			try await qso.save(on: db)

			try await app.test(.POST, "credentials/register") { req async throws in
				try req.content.encode(CredentialsAuthentificationController.CredentialsRegisterContent(accountType: .licensed, callsign: "DL2TEST", acceptTerms: "on", password: "VeryS3cre7", password_repeat: "VeryS3cre7"))
			} afterResponse: { response async in
				#expect(response.status == .seeOther)
			}

			qso = try #require(await QSO.find(try qso.requireID(), on: db))
			let hunter = try #require(await qso.$hunter.get(on: db))
			#expect(try await hunter.$callsign.get(on:db).callsign == "DL2TEST")

			#expect(try await qso.$contactedOperatorUser.get(on: db) == nil)

			try await app.test(.POST, "credentials/register") { req async throws in
				try req.content.encode(CredentialsAuthentificationController.CredentialsRegisterContent(accountType: .licensed, callsign: "DL3TEST", acceptTerms: "on", password: "VeryS3cre7", password_repeat: "VeryS3cre7"))
			} afterResponse: { response async in
				#expect(response.status == .seeOther)
			}

			qso = try #require(await QSO.find(try qso.requireID(), on: db))
			let contactedOp = try #require(await qso.$contactedOperatorUser.get(on: db))
			#expect(try await contactedOp.$callsign.get(on:db).callsign == "DL3TEST")
		}
	}
}
