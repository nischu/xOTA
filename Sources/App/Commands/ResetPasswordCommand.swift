import Vapor
import FluentKit

final class ResetPasswordCommand: AsyncCommand {

	static let name = "reset-password"

	init() {

	}

	func run(using context: ConsoleKitCommands.CommandContext, signature: Signature) async throws {

		guard let callsign = signature.callsign, !callsign.isEmpty
		else {
			context.console.error("No callsign specified.")
			throw Error.missingArgument
		}

		let db = context.application.db
		guard let userCredential = try await UserCredential.query(on: db)
			.join(Callsign.self, on: \UserCredential.$user.$id == \Callsign.$user.$id)
			.filter(Callsign.self, \.$callsign == callsign)
			.filter(UserCredential.self, \.$authProvider == CredentialsAuthentificationController.authProviderIdentifier)
			.first()
			.get()
		else {
			context.console.error("'\(callsign)' does not exist.")
			throw Error.unknownUser
		}

		userCredential.additionalStorage = try Bcrypt.hash(signature.password)
		try await userCredential.save(on: db)
		print("Chaned password for \(signature.callsign!)")
	}
	
	public var help: String {
		return "Reset password for an existing user"
	}

	public struct Signature: CommandSignature, Sendable {
		@Option(name: "callsign", short: "c", help: "Callsign to give admin privileges to.")
		var callsign: String?

		@Argument(name: "password")
		var password: String

		public init() { }
	}

	/// Errors that may be thrown when serving a server
	public enum Error: Swift.Error {
		case missingArgument
		case unknownUser
		case alreadyAdmin
	}


}

