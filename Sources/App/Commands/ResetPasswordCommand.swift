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
		guard let user = try await UserModel.query(on: db)
			.filter(\.$callsign, .equal, callsign)
			.first()
			.get()
		else {
			context.console.error("'\(callsign)' does not exist.")
			throw Error.unknownUser
		}

		user.hashedPassword = try Bcrypt.hash(signature.password)
		try await user.save(on: db)
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

