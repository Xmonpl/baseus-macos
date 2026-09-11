// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BaseusMenu",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "BaseusMenu", targets: ["BaseusMenu"])],
    targets: [
        .target(name: "BaseusProtocol"),
        .executableTarget(name: "BaseusMenu", dependencies: ["BaseusProtocol"]),
        .testTarget(name: "BaseusProtocolTests", dependencies: ["BaseusProtocol"]),
        .testTarget(name: "BaseusMenuTests", dependencies: ["BaseusMenu", "BaseusProtocol"])
    ],
    swiftLanguageModes: [.v5]
)
