import Fluent
import Foundation
import Testing
import Vapor

@testable import xOTA_App

@Suite("Award tests with DB", .serialized)
struct AwardTests: AppQueueTests {

	@Test("Test only mode specific award is created when possible")
	func onlyModeSpecificAwardIsCreatedWhenPossible() async throws {
		try await withApp { app in
			let db = app.db
			let user = try await UserModel.createUser(
				with: "DL1TEST",
				kind: .licensed,
				on: db
			)

			try await addQSO(on: db,
							 stationCall: "DL1TEST",
							 reference: "T-41",
							 call: "DL9TEST",
							 mode: .FM)

			#expect(try await Award.query(on: db).count() == 0)

			try await performAwardChecks(in: app)

			let awards = try await Award.query(on: db).all()
			#expect(awards.count == 1, "Expected 1 award, but got \(awards)")
			let award = try #require(awards.first)

			#expect(award.$user.id == user.id)
			#expect(award.kind == "activated-level-4")
			#expect(award.endorsement == "Mode: FM")
		}
	}

	@Test("Test generic award is created and later followed by mode specific ones.")
	func issueGenericAwardFollowedByEndorsementsOnceTheyAreReached() async throws {
		try await withApp { app in
			let db = app.db
			let user = try await UserModel.createUser(
				with: "DL1TEST",
				kind: .licensed,
				on: db
			)

			try await addQSO(on: db,
							 stationCall: "DL1TEST",
							 reference: "T-31",
							 call: "DL2TEST",
							 mode: .FM)

			try await addQSO(on: db,
							 stationCall: "DL1TEST",
							 reference: "T-32",
							 call: "DL3TEST",
							 mode: .SSB)

			#expect(try await Award.query(on: db).count() == 0)

			try await performAwardChecks(in: app)

			let awards = try await Award.query(on: db).all()
			#expect(awards.count == 1, "Expected 1 award, but got \(awards)")
			let award = try #require(awards.first)
			#expect(award.$user.id == user.id)
			#expect(award.kind == "activated-level-3")
			#expect(award.endorsement == nil)

			try await addQSO(on: db,
							 stationCall: "DL1TEST",
							 reference: "T-31",
							 call: "DL3TEST",
							 mode: .SSB)

			try await performAwardChecks(in: app)

			let awards2 = try await Award.query(on: db).all()
			#expect(awards2.count == 2, "Expected 2 awards, but got \(awards2)")
			let award2 = try #require(awards2.first(where: { award.id != $0.id }))
			#expect(award2.$user.id == user.id)
			#expect(award2.kind == "activated-level-3")
			#expect(award2.endorsement == "Mode: SSB")
		}
	}


	@Test("Test Ceramic and Porcelain Hunter")
	func ceramicAndPorcelainHunterMixedMode() async throws {
		try await withApp { app in
			let db = app.db
			let hunterCall = "DH1TEST"
			let user = try await UserModel.createUser(
				with: hunterCall,
				kind: .licensed,
				on: db
			)

			for i in 0...9 {
				let activatorCall = "DA\(i)TEST"
				_ = try await UserModel.createUser(with: activatorCall, kind: .licensed, on: db)
				let mode: QSO.Mode = i == 0 ? .SSB : .FM
				try await addQSO(on: db, stationCall: activatorCall, reference: "T-01", call: hunterCall, mode: mode)
			}

			#expect(try await Award.query(on: db).count() == 0)

			try await performAwardChecks(in: app)

			let awards = try await Award.query(on: db).all()
			#expect(awards.count == 1, "Expected 1 award, but got \(awards)")
			let award = try #require(awards.first)
			#expect(award.$user.id == user.id)
			#expect(award.kind == "ceramic-hunter")
			#expect(award.endorsement == nil)


			for i in 0...9 {
				let activatorCall = "DB\(i)TEST"
				_ = try await UserModel.createUser(with: activatorCall, kind: .licensed, on: db)
				let mode: QSO.Mode = i == 0 ? .SSB : .CW
				try await addQSO(on: db, stationCall: activatorCall, reference: "T-01", call: hunterCall, mode: mode)
			}

			try await performAwardChecks(in: app)

			let awards2 = try await Award.query(on: db).all()
			#expect(awards2.count == 2, "Expected 2 awards, but got \(awards2)")
			let award2 = try #require(awards2.first(where: { award.id != $0.id }))
			#expect(award2.$user.id == user.id)
			#expect(award2.kind == "porcelain-hunter")
			#expect(award2.endorsement == nil)
		}
	}

	@Test("Tri mode activated all award")
	func testTriModeCompletionistActivatorAward() async throws {
		try await withApp { app in
			let db = app.db
			let activatorCall = "DA1TEST"
			let user = try await UserModel.createUser(
				with: activatorCall,
				kind: .licensed,
				on: db
			)
			for reference in try await Reference.query(on: db).all(\.$title) {
				let hunterCall = "DH1TEST"
				for mode: QSO.Mode in [.FM, .CW, .SSTV] {
					try await addQSO(on: db, stationCall: activatorCall, reference: reference, call: hunterCall, mode: mode)
				}
			}

			#expect(try await Award.query(on: db).count() == 0)

			try await performAwardChecks(in: app)

			let allAwards = try await Award.query(on: db).all()
			let awardCount = allAwards.count

			#expect(awardCount == (6+1)*3+1+1, "Expected Activated All for all 6 levels + 1 overall  * 3 modes + 50 QSO + trimode  \(allAwards)")

			let awards = try await Award.query(on: db).filter(\.$kind, .equal, "activated-all-multi-mode-3").all()
			#expect(awards.count == 1, "Expected 1 award, but got \(awards)")
			let award = try #require(awards.first)
			#expect(award.$user.id == user.id)
			#expect(award.kind == "activated-all-multi-mode-3")
			#expect(award.name == "Tri-Mode Completionist")
			#expect(award.endorsement == "Modes: CW, FM, SSTV")
		}
	}

	@Test("Tri band activated all award")
	func testTriBandCompletionistActivatorAward() async throws {
		try await withApp { app in
			let db = app.db
			let activatorCall = "DA1TEST"
			let user = try await UserModel.createUser(
				with: activatorCall,
				kind: .licensed,
				on: db
			)
			for reference in try await Reference.query(on: db).all(\.$title) {
				let hunterCall = "DH1TEST"
				for freq in [145_500, 430_200, 1297_500] {
					let mode: QSO.Mode = reference == "T-01" && freq == 145_500 ? .CW : .FM
					try await addQSO(on: db, stationCall: activatorCall, reference: reference, call: hunterCall, mode: mode, freq: freq)
				}
			}

			#expect(try await Award.query(on: db).count() == 0)

			try await performAwardChecks(in: app)

			let allAwards = try await Award.query(on: db).all()
			let awardCount = allAwards.count

			#expect(awardCount == (6+1)+1+1, "Expected Activated All for all 6 levels + 1 overall + 50 QSO + tri bands  \(allAwards)")

			let awards = try await Award.query(on: db).filter(\.$kind, .equal, "activated-all-multi-band-3").all()
			#expect(awards.count == 1, "Expected 1 award, but got \(awards)")
			let award = try #require(awards.first)
			#expect(award.$user.id == user.id)
			#expect(award.kind == "activated-all-multi-band-3")
			#expect(award.name == "WC: Wideband Completionist")
			#expect(award.endorsement == "Bands: 2 m, 70 cm, 23 cm")

			// Add missing QSO for a mode specific tri-band award
			try await addQSO(on: db, stationCall: activatorCall, reference: "T-01", call: "DH1TEST", mode: .FM, freq: 145_500)

			try await performAwardChecks(in: app)

			let awards2 = try await Award.query(on: db).filter(\.$kind, .equal, "activated-all-multi-band-3").all()
			#expect(awards2.count == 2, "Expected 2 awards, but got \(awards2)")
			let award2 = try #require(awards2.first(where: { award.id != $0.id }))
			#expect(award2.$user.id == user.id)
			#expect(award2.kind == "activated-all-multi-band-3")
			#expect(award2.name == "WC: Wideband Completionist")
			#expect(award2.endorsement == "Bands: 2 m, 70 cm, 23 cm Mode: FM")

			// Add another QSO for the user
			try await addQSO(on: db, stationCall: activatorCall, reference: "T-01", call: "DH1TEST", mode: .FM, freq: 145_500)

			try await performAwardChecks(in: app)
			let awards3 = try await Award.query(on: db).filter(\.$kind, .equal, "activated-all-multi-band-3").all()
			#expect(awards3.count == 2, "Did not expect another award, but got \(awards3)")
		}
	}


	@Test("Activator 50 QSO award")
	func testActivatorQSOAward50() async throws {
		try await withApp { app in
			let db = app.db
			let activatorCall = "DA1TEST"
			let user = try await UserModel.createUser(
				with: activatorCall,
				kind: .licensed,
				on: db
			)

			let requiredQSOCount = 50
			// Spread the QSO over references.
			let references = try await Reference.query(on: db).all(\.$title)
			for i in 0..<requiredQSOCount {
				let hunterCall = "DH1TEST"
				let reference = references[i%references.count]
				try await addQSO(on: db, stationCall: activatorCall, reference: reference, call: hunterCall, mode: .FM)
			}

			#expect(try await Award.query(on: db).count() == 0)

			try await performAwardChecks(in: app)

			let awardCount = try await Award.query(on: db).count()
			#expect(awardCount == (6+1)+1, "Expected Activated All for all 6 levels + 1 overall + activator 50 QSO award")

			let awards = try await Award.query(on: db).filter(\.$kind, .equal, "activator-50-qso").all()
			#expect(awards.count == 1, "Expected 1 award, but got \(awards)")
			let award = try #require(awards.first)
			#expect(award.$user.id == user.id)
			#expect(award.kind == "activator-50-qso")
			#expect(award.name == "Polyuria Activator")
			#expect(award.endorsement == "Mode: FM")
		}
	}

	@Test("Activator 20 QSO same ref award")
	func testActivatorSameRef20QSO() async throws {
		try await withApp { app in
			let db = app.db
			let activatorCall = "DA1TEST"
			let user = try await UserModel.createUser(
				with: activatorCall,
				kind: .licensed,
				on: db
			)

			let requiredQSOCount = 20
			let hunterCall = "DH1TEST"
			let reference = "T-01"
			for _ in 0..<requiredQSOCount-1 {
				try await addQSO(on: db, stationCall: activatorCall, reference: reference, call: hunterCall, mode: .FM)
			}
			// Add a QSO at a different reference, the award shouldn't be issued yet.
			try await addQSO(on: db, stationCall: activatorCall, reference: "T-02", call: hunterCall, mode: .FM)

			#expect(try await Award.query(on: db).count() == 0)

			try await performAwardChecks(in: app)

			#expect(try await Award.query(on: db).count() == 0)
			// Add another QSO to achieve the required count
			try await addQSO(on: db, stationCall: activatorCall, reference: reference, call: hunterCall, mode: .CW)

			try await performAwardChecks(in: app)

			#expect(try await Award.query(on: db).count() == 1)

			let awards = try await Award.query(on: db).filter(\.$kind, .equal, "activator-same-ref-20-qso").all()
			#expect(awards.count == 1, "Expected 1 award, but got \(awards)")
			let award = try #require(awards.first)
			#expect(award.$user.id == user.id)
			#expect(award.kind == "activator-same-ref-20-qso")
			#expect(award.name == "Diaarhea Activator")
			#expect(award.endorsement == "T-01")

			try await addQSO(on: db, stationCall: activatorCall, reference: reference, call: hunterCall, mode: .FM)

			try await performAwardChecks(in: app)

			let awards2 = try await Award.query(on: db).all()
			#expect(awards2.count == 2, "Expected 2 awards, but got \(awards2)")
			let award2 = try #require(awards2.first(where: { award.id != $0.id }))
			#expect(award2.$user.id == user.id)
			#expect(award2.kind == "activator-same-ref-20-qso")
			#expect(award.name == "Diaarhea Activator")
			#expect(award2.endorsement == "T-01 Mode: FM")
		}
	}


	// MARK: – Helpers

	func performAwardChecks(in app: Application) async throws {

		try await scheduleAwardChecker(in: app)
		// Run schedule job that gets QSOs since last run and queues award checks.
		try await app.queues.queue.worker.run()
		// Clear the award checker since it would always be the next one that is picked up by the worker
		// This causes the worker to noticed it was scheduled for the future and then stop job evaluation
		clearAwardChecker(in: app)
		// Run jobs again, which should run all award check jobs in queue.
		try await app.queues.queue.worker.run()
	}

	func scheduleAwardChecker(in app: Application) async throws {
		try await app.queues.queue.dispatch(
			AwardCheckScheduler.self,
			.init(
				checkSinceDate: Date.distantPast,
				identifier: AwardCheckScheduler.jobIdentifier1.string
			),
			id: AwardCheckScheduler.jobIdentifier1
		)
	}

	func clearAwardChecker(in app: Application) {
		app.queues.asyncTest.queue = app.queues.asyncTest.queue.filter { id in
			![
				AwardCheckScheduler.jobIdentifier1,
				AwardCheckScheduler.jobIdentifier2,
			].contains(id)
		}
	}

}
