// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PesaCheckout",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "PesaCheckout", targets: ["PesaCheckout"]),
        .library(name: "PesaCheckoutCore", targets: ["PesaCheckoutCore"]),
    ],
    targets: [
        .target(name: "PesaCheckoutCore"),
        .target(name: "PesaCheckout", dependencies: ["PesaCheckoutCore"]),
        .testTarget(
            name: "PesaCheckoutCoreTests",
            dependencies: ["PesaCheckoutCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
