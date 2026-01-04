import Fluent
import Foundation
import Testing
import Vapor

@testable import xOTA_App

func addQSO(
	on db: any Database,
	stationCall: String,
	reference refName: String,
	call: String,
	contactedOperator: String? = nil,
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
		stationCallSign: stationCall,
		operator: nil,
		contactedOperator: contactedOperator,
		contactedOperatorUser: nil,
		freq: freq,
		mode: mode,
		rstSent: "59",
		rstRcvt: "59"
	).save(on: db)
}
