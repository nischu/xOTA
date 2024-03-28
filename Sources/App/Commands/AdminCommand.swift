import Vapor
import FluentKit

final class MakeAdminCommand: AsyncCommand {

	static let name = "admin"

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
		let currentRoles = try await user.$specialRoles.get(on: db)
		if signature.demote {
			for role in currentRoles {
				if role.role == .admin {
					try await role.delete(on: db)
				}
			}
			context.console.success("Removed admin privileges from '\(callsign)'.")
		} else {
			if currentRoles.first(where: { role in
				role.role == .admin
			}) != nil {
				context.console.error("'\(callsign)' is already admin.")
				throw Error.alreadyAdmin
			}
			let adminRole = UserRoleModel(role: .admin)
			try await user.$specialRoles.create(adminRole, on: db)
			context.console.success("Successfully made '\(callsign)' admin.")
		}
	}
	
	public var help: String {
		return "Make an existing user admin."
	}

	public struct Signature: CommandSignature, Sendable {
		@Option(name: "callsign", short: "c", help: "Callsign to give admin privileges to.")
		var callsign: String?

		@Flag(name: "demote", short: "d", help: "Demote user and remove admin privileges.")
		var demote: Bool

		public init() { }
	}

	/// Errors that may be thrown when serving a server
	public enum Error: Swift.Error {
		case missingArgument
		case unknownUser
		case alreadyAdmin
	}


}

