import Vapor

struct VisualizationController: RouteCollection {
	let namingTheme: NamingTheme

	func boot(routes: any RoutesBuilder) throws {
		let viz = routes.grouped("viz")
		viz.get("graph", use: graph(req:))
	}

	func graph(req: Request) async throws -> View {
		struct Context: Content {
			var showNav: Bool
			var common: CommonContent
		}
		let showNav = try req.query.get(Bool?.self, at: "hideNav") != true
		return try await req.view.render("viz-force-graph", Context(showNav:showNav, common: req.commonContent))
	}
}
