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
			var margin: Int
			var refresh: Int?
			var showTitle: Bool
			var common: CommonContent
		}
		let showNav = try req.query.get(Bool?.self, at: "hideNav") != true
		let width = try req.query.get(Int?.self, at: "width")
		let height = try req.query.get(Int?.self, at: "height")
		let margin = try req.query.get(Int?.self, at: "margin") ?? 50
		var refresh = try req.query.get(Int?.self, at: "refresh")
		if let refreshArg = refresh, refreshArg < 60 {
			refresh = 60
		}
		let showTitle = try req.query.get(Bool?.self, at: "showTitle") ?? false

		return try await req.view.render("viz-force-graph", Context(showNav:showNav, width: width, height: height, margin: margin, refresh: refresh, showTitle: showTitle, common: req.commonContent))
	}
}
