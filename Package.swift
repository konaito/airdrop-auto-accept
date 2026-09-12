// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AirDropAutoAccept",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AirDropAutoAccept", targets: ["AirDropAutoAccept"])
    ],
    targets: [
        .executableTarget(name: "AirDropAutoAccept")
    ]
)
