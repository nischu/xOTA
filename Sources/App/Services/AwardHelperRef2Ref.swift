import Vapor

struct AwardHelperRef2Ref {
	let awardKind: Award.AwardKind = "activated"

	func hasRef2Ref(for user: UserModel, app: Application, refNameA: String, refNameB: String) async throws -> Bool {
		let userId = try user.requireID()
		let referenceIds = try await Reference.query(on: app.db).group(.or, { query in
			query
				.filter(\.$title, .equal, refNameA)
				.filter(\.$title, .equal ,refNameB)
		}).all(\.$id)

		guard referenceIds.count == 2 else {
			app.logger.warning("AwardHelperRef2Ref only only found \(referenceIds.count) for reference names '\(refNameA)' and '\(refNameB)'.")
			return false
		}

		let qsosCount = try await QSO.query(on: app.db)
			.filter(\.$activator.$id, .equal, userId)
			.group(.or) { query in
				query
					.group { query in
						// Activated A hunt B
						query
							.filter(\.$reference.$id, .equal, referenceIds[0])
							.filter(\.$huntedReference.$id, .equal, referenceIds[1])
					}
					.group { query in
						// Activated B hunt A
						query
							.filter(\.$reference.$id, .equal, referenceIds[1])
							.filter(\.$huntedReference.$id, .equal, referenceIds[0])
					}
			}
			.count()
		// Currently we only check if any activator QSO is logged connecting both references.
		// Ideally we'd match up two Ref2Ref QSOs and only issue the award if the other station confirmed the Ref2Ref.
		return qsosCount > 0
	}


}
