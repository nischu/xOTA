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
			var width: Int?
			var height: Int?
			var common: CommonContent
		}
		let showNav = try req.query.get(Bool?.self, at: "hideNav") != true
		let width = try req.query.get(Int?.self, at: "width") ?? 0
		let height = try req.query.get(Int?.self, at: "height") ?? 0

		return try await req.view.render("viz-force-graph", Context(showNav:showNav, width: width, height: height, common: req.commonContent))
	}
}
