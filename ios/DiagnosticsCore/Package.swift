// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DiagnosticsCore",
    products: [.library(name: "DiagnosticsCore", targets: ["DiagnosticsCore"])],
    targets: [
        .target(name: "DiagnosticsCore"),
        .testTarget(name: "DiagnosticsCoreTests", dependencies: ["DiagnosticsCore"]),
    ]
)
