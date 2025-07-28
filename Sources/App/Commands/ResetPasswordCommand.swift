import Vapor
import FluentKit

final class ResetPasswordCommand: AsyncCommand {

	static let name = "reset-password"

	init() {

	}

	func run(using context: ConsoleKitCommands.CommandContext, signature: Signature) async throws {

		guard let callsign = normalizedCallsignOptional(signature.callsign), !callsign.isEmpty
		else {
			context.console.error("No callsign specified.")
			throw Error.missingArgument
		}

		let db = context.application.db
		guard let userId = try await UserModel.userFor(callsign: callsign, on: db).get()?.id
		else {
			context.console.error("'\(callsign)' does not exist.")
			throw Error.unknownUser
		}

		var userCredential = try await UserCredential.query(on: db)
			.filter(UserCredential.self, \.$loginIdentifier == callsign)
			.filter(\.$authProvider == CredentialsAuthentificationController.authProviderIdentifier)
			.first()

		let addCredentials = signature.add && userCredential == nil
		if addCredentials {
			userCredential = UserCredential(userId: userId, authProvider: CredentialsAuthentificationController.authProviderIdentifier, loginIdentifier: callsign, additionalStorage: nil)
		}

		guard let userCredential else {
			context.console.error("'\(callsign)' does not use password auth. Use --add flag to add a password.")
			throw Error.noPassword
		}

		userCredential.additionalStorage = try Bcrypt.hash(signature.password)
		try await userCredential.save(on: db)
		if addCredentials {
			print("Added password for \(signature.callsign!)")
		} else {
			print("Updated password for \(signature.callsign!)")
		}
	}
	
	public var help: String {
		return "Reset password for an existing user"
	}

	public struct Signature: CommandSignature, Sendable {
		@Option(name: "callsign", short: "c", help: "Callsign to give admin privileges to.")
		var callsign: String?

		@Argument(name: "password")
		var password: String

		@Flag(name: "add")
		var add: Bool

		public init() { }
	}

	/// Errors that may be thrown when serving a server
	public enum Error: Swift.Error {
		case missingArgument
		case unknownUser
		case noPassword
	}


}

