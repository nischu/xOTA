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

	func addQSO(
		on db: any Database,
		stationCall: String,
		reference refName: String,
		call: String,
		huntedReference huntedRefName: String? = nil,
		mode: QSO.Mode,
		freq: Int = 430_200,
		rstSent: String = "59",
		rstRcvt: String = "59"
	) async throws {

		let reference = try #require(
			await Reference.query(on: db).filter(\.$title, .equal, refName)
				.first()
		)
		let user = try #require(
			try await Callsign.callsign(stationCall, on: db).with(\.$user)
				.first()?.user
		)

		let hunter = try await Callsign.callsign(call, on: db).with(\.$user)
				.first()?.user

		let huntedReference: Reference? = if let huntedRefName {
			try await Reference.query(on: db).filter(\.$title, .equal, huntedRefName).first()
		} else {
			nil
		}

		try await QSO(
			id: nil,
			activator: user,
			activatorTrainer: nil,
			hunter: hunter,
			reference: reference,
			huntedReference: huntedReference,
			date: Date(),
			call: call,
			stationCallSign: "DL2TEST",
			operator: nil,
			contactedOperator: nil,
			contactedOperatorUser: nil,
			freq: 430_200,
			mode: mode,
			rstSent: "59",
			rstRcvt: "59"
		).save(on: db)
	}


}
