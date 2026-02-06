// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftTUIKit",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SwiftTUIKit",
            targets: ["SwiftTUIKit"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SwiftTUIKit"
        ),
        .executableTarget(
            name: "SwiftTUIKitExampleChatSimple",
            dependencies: ["SwiftTUIKit"],
            path: "Examples/ChatSimple"
        ),
        .executableTarget(
            name: "SwiftTUIKitExampleKeyTester",
            dependencies: ["SwiftTUIKit"],
            path: "Examples/KeyTester"
        ),
        .executableTarget(
            name: "SwiftTUIKitExampleOverlayDemo",
            dependencies: ["SwiftTUIKit"],
            path: "Examples/OverlayDemo"
        ),
        .executableTarget(
            name: "SwiftTUIKitExampleSelectList",
            dependencies: ["SwiftTUIKit"],
            path: "Examples/SelectList"
        ),
        .executableTarget(
            name: "SwiftTUIKitExampleSettingsList",
            dependencies: ["SwiftTUIKit"],
            path: "Examples/SettingsList"
        ),
        .executableTarget(
            name: "SwiftTUIKitExampleMarkdown",
            dependencies: ["SwiftTUIKit"],
            path: "Examples/Markdown"
        ),
        .executableTarget(
            name: "SwiftTUIKitExampleEditor",
            dependencies: ["SwiftTUIKit"],
            path: "Examples/Editor"
        ),
        .executableTarget(
            name: "SwiftTUIKitExampleImage",
            dependencies: ["SwiftTUIKit"],
            path: "Examples/Image"
        ),
        .testTarget(
            name: "SwiftTUIKitTests",
            dependencies: ["SwiftTUIKit"]
        ),
    ]
)
