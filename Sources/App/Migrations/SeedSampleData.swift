import Fluent
import Foundation

struct SeedSampleData: AsyncMigration {
	func prepare(on database: Database) async throws {

		let references = [
			Reference(title: "T-01", website: "https://38c3.c3nav.de/l/tota-t-01/"),
			Reference(title: "T-02", website: "https://38c3.c3nav.de/l/tota-t-02/"),
			Reference(title: "T-03", website: "https://38c3.c3nav.de/l/tota-t-03/"),
			Reference(title: "T-04", website: "https://38c3.c3nav.de/l/tota-t-04/"),
			Reference(title: "T-11", website: "https://38c3.c3nav.de/l/tota-t-11/"),
			Reference(title: "T-12", website: "https://38c3.c3nav.de/l/tota-t-12/"),
			Reference(title: "T-13", website: "https://38c3.c3nav.de/l/tota-t-13/"),
			Reference(title: "T-14", website: "https://38c3.c3nav.de/l/tota-t-14/"),
			Reference(title: "T-21", website: "https://38c3.c3nav.de/l/tota-t-21/"),
			Reference(title: "T-22", website: "https://38c3.c3nav.de/l/tota-t-22/"),
			Reference(title: "T-23", website: "https://38c3.c3nav.de/l/tota-t-23/"),
			Reference(title: "T-24", website: "https://38c3.c3nav.de/l/tota-t-24/"),
			Reference(title: "T-31", website: "https://38c3.c3nav.de/l/tota-t-31/"),
			Reference(title: "T-32", website: "https://38c3.c3nav.de/l/tota-t-32/"),
			Reference(title: "T-41", website: "https://38c3.c3nav.de/l/tota-t-41/"),
			Reference(title: "T-91", website: "https://38c3.c3nav.de/l/tota-t-91/"),
		]

		for reference in references {
			try await reference.save(on: database)
		}


		let userN0CALL = try await database.transaction { database in
			let userN0CALL = try await UserModel.createUser(with: "N0CALL", kind: .licensed, on: database)
			// Add training callsign
			let trainingCall = Callsign(callsign: "N0CALL/T", kind: .training)
			trainingCall.$user.id = try userN0CALL.requireID()
			try await trainingCall.save(on: database)
			return userN0CALL
		}

		let userN0CALA = try await UserModel.createUser(with: "N0CALA", kind: .licensed, on: database)

		let qsos = [
			try QSO(activator:userN0CALL, activatorTrainer: nil, hunter: userN0CALA, reference: references[0], date: Date(timeIntervalSinceNow: -15), call: "N0CALA", stationCallSign: "N0CALL", operator:nil, contactedOperator: nil, contactedOperatorUser: nil, freq: 145000, mode: .FM, rstSent: "59", rstRcvt: "59"),
			try QSO(activator:userN0CALL, activatorTrainer: nil, hunter: nil, reference: references[0], date: Date(timeIntervalSinceNow: -10), call: "N0CALB", stationCallSign: "N0CALL", operator:nil, contactedOperator: nil, contactedOperatorUser: nil, freq: 145000, mode: .FM, rstSent: "59", rstRcvt: "59"),
			try QSO(activator:userN0CALL, activatorTrainer: nil, hunter: nil, reference: references[0], date: Date(timeIntervalSinceNow: -5), call: "N0CALC", stationCallSign: "N0CALL", operator:nil, contactedOperator: nil, contactedOperatorUser: nil, freq: 145000, mode: .FM, rstSent: "59", rstRcvt: "59"),
			try QSO(activator:userN0CALL, activatorTrainer: nil, hunter: nil, reference: references[0], date: Date(timeIntervalSinceNow: -0), call: "N0CALD", stationCallSign: "N0CALL", operator:nil, contactedOperator: nil, contactedOperatorUser: nil, freq: 145000, mode: .FM, rstSent: "59", rstRcvt: "59"),

			try QSO(activator:userN0CALA, activatorTrainer: nil, hunter: userN0CALA, reference: references[0], date: Date(timeIntervalSinceNow: -10), call: "N0CALL", stationCallSign: "N0CALA", operator: nil, contactedOperator: nil, contactedOperatorUser: nil, freq: 145000, mode: .FM, rstSent: "59", rstRcvt: "59"),
		]

		for qso in qsos {
			try await qso.save(on: database)
		}
	}

	func revert(on database: Database) async throws {
		
	}
}
