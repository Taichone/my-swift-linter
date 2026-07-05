// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "my-swift-linter",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/Ryu0118/swift-ast-lint.git", from: "0.3.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0" ..< "700.0.0"),
    ],
    targets: [
        .target(
            name: "Rules",
            dependencies: [
                .product(name: "SwiftASTLint", package: "swift-ast-lint"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),
        .executableTarget(
            name: "my-swift-linter",
            dependencies: [
                "Rules",
                .product(name: "SwiftASTLint", package: "swift-ast-lint"),
            ]
        ),
        .testTarget(
            name: "RulesTests",
            dependencies: [
                "Rules",
                .product(name: "SwiftASTLintTestSupport", package: "swift-ast-lint"),
            ]
        ),
    ]
)
