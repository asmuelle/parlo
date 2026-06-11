// swift-tools-version: 6.2
// Parlo — on-device AI speaking partner (iOS-first).
// Core domain packages for M0/M1. Every target builds and tests on macOS via
// `swift test`; platform AI (FoundationModels, Speech) sits behind protocol
// seams with deterministic mocks (see DESIGN.md + AGENTS.md invariants).
import PackageDescription

let package = Package(
    name: "ParloPackages",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ParloKit", targets: ["ParloKit"]),
        .library(name: "ConversationEngine", targets: ["ConversationEngine"]),
        .library(name: "SpeechKit", targets: ["SpeechKit"]),
        .library(name: "PronunciationBeta", targets: ["PronunciationBeta"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Paywall", targets: ["Paywall"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    targets: [
        .target(
            name: "ParloKit",
            path: "Packages/ParloKit/Sources",
        ),
        .testTarget(
            name: "ParloKitTests",
            dependencies: ["ParloKit"],
            path: "Packages/ParloKit/Tests",
        ),
        .target(
            name: "ConversationEngine",
            dependencies: ["ParloKit"],
            path: "Packages/ConversationEngine/Sources",
        ),
        .testTarget(
            name: "ConversationEngineTests",
            dependencies: ["ConversationEngine"],
            path: "Packages/ConversationEngine/Tests",
            resources: [.copy("Fixtures")],
        ),
        .target(
            name: "SpeechKit",
            dependencies: ["ParloKit"],
            path: "Packages/SpeechKit/Sources",
        ),
        .testTarget(
            name: "SpeechKitTests",
            dependencies: ["SpeechKit"],
            path: "Packages/SpeechKit/Tests",
        ),
        .target(
            name: "PronunciationBeta",
            dependencies: ["ParloKit"],
            path: "Packages/PronunciationBeta/Sources",
        ),
        .testTarget(
            name: "PronunciationBetaTests",
            dependencies: ["PronunciationBeta"],
            path: "Packages/PronunciationBeta/Tests",
        ),
        .target(
            name: "Persistence",
            dependencies: ["ParloKit"],
            path: "Packages/Persistence/Sources",
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"],
            path: "Packages/Persistence/Tests",
        ),
        .target(
            name: "Paywall",
            dependencies: ["ParloKit"],
            path: "Packages/Paywall/Sources",
        ),
        .testTarget(
            name: "PaywallTests",
            dependencies: ["Paywall"],
            path: "Packages/Paywall/Tests",
        ),
        .target(
            name: "DesignSystem",
            path: "Packages/DesignSystem/Sources",
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"],
            path: "Packages/DesignSystem/Tests",
        ),
    ],
)
