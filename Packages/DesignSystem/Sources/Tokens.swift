import Foundation

/// Design tokens for the "travel journal at a café table" direction
/// (DESIGN.md): warm, analog, personal — the opposite of gamified neon.
/// Raw sRGB components live here so token values are unit-testable; SwiftUI
/// adapters are in TokensSwiftUI.swift.
public struct ColorToken: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// Relative luminance approximation (sRGB, linearized).
    public var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

public enum ParloPalette {
    /// Warm paper cream — light UI default surface (oklch ≈ 97% 0.02 85).
    public static let paperCream = ColorToken(red: 0.972, green: 0.945, blue: 0.890)
    /// Slightly deeper paper for cards, like a journal page edge.
    public static let cardPaper = ColorToken(red: 0.945, green: 0.910, blue: 0.840)
    /// Espresso ink — primary text.
    public static let espressoInk = ColorToken(red: 0.184, green: 0.149, blue: 0.118)
    /// Terracotta — primary accent (actions, learner bubbles).
    public static let terracotta = ColorToken(red: 0.761, green: 0.416, blue: 0.290)
    /// Olive — secondary accent (meters, stamps, quiet emphasis).
    public static let olive = ColorToken(red: 0.478, green: 0.490, blue: 0.314)
    /// Deep teal — reserved *semantically* for corrections. Corrections are
    /// calm, never red or alarming: shy learners are a core segment.
    public static let correctionTeal = ColorToken(red: 0.122, green: 0.431, blue: 0.420)
}

public enum ParloSpacing {
    public static let xs: Double = 4
    public static let sm: Double = 8
    public static let md: Double = 16
    public static let lg: Double = 24
    public static let xl: Double = 40
}

public enum ParloRadius {
    /// Bubbles are soft and rounded; cards a touch crisper, like paper.
    public static let bubble: Double = 18
    public static let card: Double = 10
    public static let chip: Double = 14
}

public enum ParloMotion {
    /// Conversation bubbles settle with a gentle spring (DESIGN.md).
    public static let bubbleSpringResponse: Double = 0.45
    public static let bubbleSpringDamping: Double = 0.82
    /// The naturalness meter fills like ink: slow, smooth.
    public static let inkFillDuration: Double = 0.6
}
