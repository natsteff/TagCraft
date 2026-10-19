// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "TagCraft", platforms: [.macOS(.v14)], products: [.executable(name: "TagCraft", targets: ["TagCraft"])], targets: [.executableTarget(name: "TagCraft"), .testTarget(name: "TagCraftTests", dependencies: ["TagCraft"])])
