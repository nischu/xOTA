import Vapor
import NIOConcurrencyHelpers

final class WebSocketManager: @unchecked Sendable, LifecycleHandler {
	private let lock: NIOLock
	private var connections: Set<WebSocket>
	var connectionCount: Int {
		return connections.count
	}

	init() {
		self.lock = NIOLock()
		self.connections = .init()
	}

	func track(_ ws: WebSocket) {
		self.lock.lock()
		defer { self.lock.unlock() }
		self.connections.insert(ws)
		ws.onClose.whenComplete { event in
			self.lock.lock()
			defer { self.lock.unlock() }
			self.connections.remove(ws)
		}
	}

	func broadcast(_ message: String) {
		self.lock.lock()
		defer { self.lock.unlock() }
		for ws in self.connections {
			ws.send(message)
		}
	}

	func broadcast(_ message: @autoclosure () async throws -> any Encodable) async throws {
		self.lock.lock()
		defer { self.lock.unlock() }
		guard !self.connections.isEmpty else { return }

		let data = try await JSONEncoder().encode(message())
		for ws in self.connections {
			try await ws.send([UInt8](data))
		}
	}

	/// Closes all active WebSocket connections
	func shutdown(_ app: Application) {
		self.lock.lock()
		defer { self.lock.unlock() }
		app.logger.debug("Shutting down \(self.connections.count) WebSocket(s)")
		try! EventLoopFuture<Void>.andAllSucceed(
			self.connections.map { $0.close() } ,
			on: app.eventLoopGroup.next()
		).wait()
	}
}

#if compiler(<6)
extension WebSocket: Equatable {}
extension WebSocket: Hashable {}
#else
extension WebSocket: @retroactive Equatable {}
extension WebSocket: @retroactive Hashable {}
#endif
extension WebSocket {
	public static func == (lhs: WebSocket, rhs: WebSocket) -> Bool {
		lhs === rhs
	}

	public func hash(into hasher: inout Hasher) {
		ObjectIdentifier(self).hash(into: &hasher)
	}
}

struct WebSocketManagerKey: StorageKey {
	typealias Value = WebSocketManager
}

struct WebSocketManagerSpotsKey: StorageKey {
	typealias Value = WebSocketManager
}

extension Application {

	var webSocketManager: WebSocketManager? {
		get {
			self.storage[WebSocketManagerKey.self]
		}
		set {
			self.storage[WebSocketManagerKey.self] = newValue
		}
	}

	var webSocketManagerSpots: WebSocketManager? {
		get {
			self.storage[WebSocketManagerSpotsKey.self]
		}
		set {
			self.storage[WebSocketManagerSpotsKey.self] = newValue
		}
	}

}
