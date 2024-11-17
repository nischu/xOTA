import Vapor

struct APIController: RouteCollection {
	let namingTheme: NamingTheme
	func boot(routes: RoutesBuilder) throws {
		routes.get("api") { req -> [String] in
			let routes = req.application.routes.all.filter { $0.path.starts(with: ["api"])}
			return routes.map(\.description)
		}
	}
}
