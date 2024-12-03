import Vapor

struct APIController: RouteCollection {
	let namingTheme: NamingTheme
	func boot(routes: RoutesBuilder) throws {
		routes.get("api") { req -> String in
			let routes = req.application.routes.all.filter { $0.path.starts(with: ["api"])}
			return routes.map { route in
				[route.method.rawValue, route.path.map({$0.description}).joined(separator: "/"), (route.userInfo["description"] as? String)].compacted().joined(separator: "\t")
			}
			.joined(separator: "\n")
		}.description("This page. No auth required.")
	}
}
