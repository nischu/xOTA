@testable import xOTA_App

import Fluent
import Testing
import XCTVapor
import XCTQueues



@Suite("User Deletion Tests with DB", .serialized)
struct UserDeletionTests {
	private func withApp(_ test: (Application) async throws -> ()) async throws {
		let app = try await Application.make(.testing)
		do {
			try await configure(app)
			app.queues.use(.asyncTest)
			try await app.autoMigrate()
			try await test(app)
		}
		catch {
			try await app.asyncShutdown()
			throw error
		}
		try await app.asyncShutdown()
	}

	@Test("Test User Deletion cleans up awards on Disk")
	func awardFileDeletedOnUserDelete() async throws {
		try await withApp { app in
			var cookies: HTTPCookies?
			try await app.test(.POST, "credentials/register") { req async throws in
				try req.content.encode(CredentialsAuthentificationController.CredentialsRegisterContent(accountType: .licensed, callsign: "DL2TEST", acceptTerms: "on", password: "VeryS3cre7", password_repeat: "VeryS3cre7"))
			} afterResponse: { response async in
				#expect(response.status == .seeOther)
				cookies = response.headers.setCookie
			}

			let user = try #require(await UserModel.userFor(callsign: "DL2TEST", on: app.db).get())
			// Generate fake test award.
			let award = try Award(userId: user.requireID(), kind: "test-award", name: "TestAward Name")
			award.state = .rendering
			try await award.save(on: app.db)
			let awardId = try award.requireID()
			let awardIdString = awardId.uuidString
			let filename = "rendered-awards/\(awardIdString)/test_award.txt"
			award.filename = filename
			let fullAwardPath = "Public/".appending(filename)
			let fullAwardContainerPath = "Public/rendered-awards/\(awardIdString)/"
			let fileManager = FileManager.default
			try fileManager.createDirectory(atPath: fullAwardContainerPath, withIntermediateDirectories: true)
			#expect(fileManager.createFile(atPath: fullAwardPath, contents: Data()))
			#expect(fileManager.fileExists(atPath: fullAwardPath))
			award.state = .issued
			try await award.save(on: app.db)

			try await app.test(.POST, "profile/delete") { req async throws in
				req.headers.cookie = cookies
				try req.content.encode(["confirm" : "on"])
			} afterResponse: { response async in
				#expect(response.status == .ok)
			}

			try await app.queues.queue.worker.run()

			#expect(!fileManager.fileExists(atPath: fullAwardPath))
			#expect(!fileManager.fileExists(atPath: fullAwardContainerPath))
			
			#expect(try await Award.find(awardId, on: app.db) == nil)
			#expect(try await UserModel.userFor(callsign: "DL2TEST", on: app.db).get() == nil)
		}
	}

}
