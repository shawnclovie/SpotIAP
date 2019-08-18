// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "SpotIAP",
	platforms: [
		.iOS(8.0), .macOS(10.11),
	],
    products: [
        .library(
            name: "SpotIAP",
            targets: ["SpotIAP"]),
    ],
    dependencies: [
		.package(url: "https://github.com/shawnclovie/Spot", .branch("master")),
		.package(url: "https://github.com/shawnclovie/SpotSQLite", .branch("master")),
    ],
    targets: [
        .target(
            name: "SpotIAP",
            dependencies: ["Spot", "SpotSQLite"]),
    ]
)
