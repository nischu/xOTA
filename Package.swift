// swift-tools-version:5.9
import PackageDescription

let package = Package(
	name: "xOTA",
	platforms: [
		.macOS(.v13)
	],
	dependencies: [
		// 💧 A server-side Swift web framework.
		.package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
		// 🗄 An ORM for SQL and NoSQL databases.
		.package(url: "https://github.com/vapor/fluent.git", from: "4.8.0"),
		// Fluent driver for SQLite.
		.package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.6.0"),
		// 🍃 An expressive, performant, and extensible templating language built for Swift.
		.package(url: "https://github.com/vapor/leaf.git", from: "4.2.4"),
		// OAuth with Hub
		.package(url: "https://github.com/vapor-community/Imperial.git", from: "1.0.0"),
		.package(url: "https://github.com/apple/swift-crypto.git", from: "3.1.0"),
	],
	targets: [
		.executableTarget(
			name: "App",
			dependencies: [
				.product(name: "Vapor", package: "vapor"),
				.product(name: "Fluent", package: "fluent"),
				.product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
				.product(name: "Leaf", package: "leaf"),
				.target(name: "ImperialCCCHub"),
			]
		),
		.target(name: "ImperialCCCHub", dependencies: [
			.product(name: "ImperialCore", package: "Imperial"),
			.product(name: "Crypto", package: "swift-crypto"),
		]),
		.testTarget(name: "AppTests", dependencies: [
			.target(name: "App"),
			.product(name: "XCTVapor", package: "vapor"),

			// Workaround for https://github.com/apple/swift-package-manager/issues/6940
			.product(name: "Vapor", package: "vapor"),
		])
	]
)
